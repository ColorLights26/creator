import Foundation
import CoreGraphics
import CoreText
import ImageIO
import Metal
import simd

/// Session-owned identity, never part of a persistent scene recipe.
struct SceneCatalogSongContent: Equatable {
  let identity: String
  let title: String
  let artist: String
  let artwork: Data?
  let accent: UInt32

  static func parse(_ value: [String: Any]) -> Self? {
    guard Set(value.keys).isSubset(of: ["schemaVersion", "identity", "title", "artist", "artworkBytes", "accentArgb"]),
      let schema = value["schemaVersion"] as? NSNumber,
      CFGetTypeID(schema) != CFBooleanGetTypeID(), schema.doubleValue == 1,
      let identity = value["identity"] as? String, !identity.isEmpty, identity.utf16.count <= 512,
      let title = value["title"] as? String, !title.isEmpty, title.utf16.count <= 512,
      value["artist"] == nil || value["artist"] is String,
      let accent = value["accentArgb"] as? NSNumber,
      CFGetTypeID(accent) != CFBooleanGetTypeID(), accent.doubleValue.isFinite,
      accent.doubleValue.rounded() == accent.doubleValue,
      (0...Double(UInt32.max)).contains(accent.doubleValue)
    else { return nil }
    let artist = value["artist"] as? String ?? ""
    guard artist.utf16.count <= 512 else { return nil }
    let artwork = value["artworkBytes"] as? Data
    guard value["artworkBytes"] == nil || artwork != nil,
      artwork == nil || (1...2_097_152).contains(artwork!.count) else { return nil }
    return Self(identity: identity, title: title, artist: artist, artwork: artwork, accent: accent.uint32Value)
  }
}

/// The existing scene supplies signals and host time. No clock or detector.
final class SceneCatalogSongStripState {
  private(set) var bars = [Float](repeating: 0, count: 45)
  private(set) var pulse: Float = 0
  private(set) var haloEnergy: Float = 0
  private var frame: SceneRenderSignalFrameV2?
  private var previousHost: Double?
  private var playing = false
  private var lastSession: Int64 = -1
  private var serials: [Int64] = [0, 0, 0, 0]
  private var pendingStrength: Float = 0
  private var peak: Float = 0
  private var attackRemaining: Double = 0
  private var lastTrigger: Double = -10

  var needsFrames: Bool {
    playing && (frame.map { $0.available && $0.fresh && $0.musicActive } == true ||
      pulse > 0 || haloEnergy > 0 || bars.contains { $0 > 0 })
  }

  func consume(_ next: SceneRenderSignalFrameV2) -> Bool {
    let newSession = next.sessionId != lastSession
    if newSession { reset(); lastSession = next.sessionId }
    let events = [next.beat, next.accent, next.impact, next.flash]
    if next.available && next.fresh && next.musicActive && !newSession {
      if next.usesMappedMusicAuthority {
        // MusicMap's beat grid travels as phase, independently of its sparse
        // transition/drop cues. Observe an actual wrap; never predict beats.
        if (next.beat.active && next.beat.serial > serials[0]) || mappedBeatCrossed(next) {
          pendingStrength = max(pendingStrength, 0.75 + 0.25 * unit(next.dynamics[2]))
        }
      } else {
        let floors: [Float] = [0.65, 0.60, 0.55, 0]
        for i in events.indices where events[i].active && events[i].serial != serials[i] {
          pendingStrength = max(pendingStrength, floors[i] + (1 - floors[i]) * unit(events[i].strength))
        }
      }
    }
    serials = events.map(\.serial)
    frame = next
    return true
  }

  private func mappedBeatCrossed(_ next: SceneRenderSignalFrameV2) -> Bool {
    guard let previous = frame, previous.usesMappedMusicAuthority,
      previous.available, previous.fresh, previous.musicActive,
      next.audioTimestampMicros > previous.audioTimestampMicros,
      next.audioTimestampMicros - previous.audioTimestampMicros <= 250_000
    else { return false }
    // A discontinuity re-establishes the baseline instead of flashing on seek
    // or after a stalled transport. Normal admission delivers at 30 Hz.
    return unit(previous.rhythm[1]) - unit(next.rhythm[1]) > 0.5
  }

  func setPlaying(_ next: Bool, hostTime: Double) {
    playing = next
    if !next { reset() }
    previousHost = hostTime
  }

  func advance(hostTime: Double, reducedMotion: Bool) {
    guard playing, !reducedMotion, hostTime.isFinite else { reset(); return }
    let dt = min(max(previousHost.map { hostTime - $0 } ?? 1 / 30, 0), 0.1)
    previousHost = hostTime
    let reactive = frame.map { $0.available && $0.fresh && $0.musicActive } ?? false
    if pendingStrength > 0 && hostTime - lastTrigger >= 0.18 {
      peak = pendingStrength; attackRemaining = 0.035; lastTrigger = hostTime
    }
    pendingStrength = 0
    if attackRemaining > 0 {
      pulse += (peak - pulse) * Float(1 - exp(-dt / 0.012))
      attackRemaining -= dt
    } else { pulse *= Float(exp(-dt / 0.30)) }
    if pulse < 0.0001 { pulse = 0 }
    let energy = reactive ? unit(frame!.dynamics[2]) : 0
    let mapped = frame?.usesMappedMusicAuthority == true
    let bass = reactive ? (mapped ? energy : unit(frame!.spectrumSummary[1])) : 0
    haloEnergy = smooth(haloEnergy, energy * 0.4 + bass * 0.6, dt: dt, attack: 0.075, release: 0.28)
    for i in bars.indices {
      var band: Float = 0
      if reactive && !mapped {
        let spectrum = frame!.smoothedSpectrum
        let position = Float(i) / 44 * Float(spectrum.count - 1)
        let low = Int(position), high = min(low + 1, spectrum.count - 1)
        band = unit(spectrum[low]) * (1 - (position - Float(low))) + unit(spectrum[high]) * (position - Float(low))
      }
      let target: Float = !reactive ? 0 : mapped ? energy * 0.7 + pulse * 0.3 : band * 0.78 + energy * 0.12 + pulse * 0.10
      bars[i] = smooth(bars[i], unit(target), dt: dt, attack: 0.055, release: 0.21)
    }
  }

  private func reset() {
    for i in bars.indices { bars[i] = 0 }
    pulse = 0; haloEnergy = 0; pendingStrength = 0; peak = 0
    attackRemaining = 0; lastTrigger = -10; frame = nil; previousHost = nil
    lastSession = -1; serials = [0, 0, 0, 0]
  }

  private func unit(_ value: Float) -> Float { value.isFinite ? min(max(value, 0), 1) : 0 }
  private func smooth(_ current: Float, _ target: Float, dt: Double, attack: Double, release: Double) -> Float {
    let value = current + (target - current) * Float(1 - exp(-dt / (target > current ? attack : release)))
    return value < 0.0001 ? 0 : value
  }
}

/// One GPU output; song artwork and text are rasterized only on content/size
/// changes. The existing allocator owns output lifetime and backpressure.
@available(iOS 15.0, *)
final class SceneCatalogSongStripRenderer {
  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let pipeline: MTLRenderPipelineState
  private var identityTexture: MTLTexture?
  private var rasterKey: String?
  private var content: SceneCatalogSongContent?
  private var contentRevision = 0
  private(set) var identityRasterCount = 0

  init(device: MTLDevice) throws {
    self.device = device
    guard let queue = device.makeCommandQueue() else { throw Failure.graphics }
    self.queue = queue
    let library = try device.makeLibrary(source: Self.source, options: nil)
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = library.makeFunction(name: "songStripVertex")
    descriptor.fragmentFunction = library.makeFunction(name: "songStripFragment")
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
  }

  @discardableResult
  func updateSongContent(_ next: SceneCatalogSongContent?) -> Bool {
    guard next != content else { return false }
    content = next; contentRevision += 1; rasterKey = nil
    return true
  }

  func render(state: SceneCatalogSongStripState, logicalSize: CGSize, hostTime: Double,
      reducedMotion: Bool, width: Int, height: Int,
      outputAllocator: SceneSurfaceNativeOutputAllocator) throws -> MTLTexture {
    guard width > 0, height > 0, width <= 8192, height <= 8192,
      logicalSize.width > 0, logicalSize.height > 0 else { throw Failure.dimensions }
    state.advance(hostTime: hostTime, reducedMotion: reducedMotion)
    let scale = min(1.25, min(logicalSize.width / 402, logicalSize.height / 650))
    let top = (logicalSize.height - 285.75 * scale) * 0.425
    try prepareIdentity(logicalSize: logicalSize, top: top, scale: scale, width: width, height: height)
    let tones = Self.tones(content?.accent ?? 0xffc65bff)
    var uniforms: [Float] = [Float(logicalSize.width), Float(logicalSize.height), Float(scale), Float(top),
      Float(top + 235.75 * scale), state.pulse, state.haloEnergy]
    uniforms += state.bars
    uniforms += [tones.0.x, tones.0.y, tones.0.z, tones.1.x, tones.1.y, tones.1.z]
    guard let output = try SceneSurfaceNativeOutputAllocator.makeTexture(device: device,
      width: width, height: height, allocator: outputAllocator), let command = queue.makeCommandBuffer()
    else { throw Failure.graphics }
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = output
    pass.colorAttachments[0].loadAction = .dontCare
    pass.colorAttachments[0].storeAction = .store
    guard let encoder = command.makeRenderCommandEncoder(descriptor: pass), let identityTexture
    else { throw Failure.graphics }
    encoder.setRenderPipelineState(pipeline)
    uniforms.withUnsafeBufferPointer { buffer in
      encoder.setFragmentBytes(buffer.baseAddress!, length: buffer.count * MemoryLayout<Float>.size, index: 0)
    }
    encoder.setFragmentTexture(identityTexture, index: 0)
    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    encoder.endEncoding()
    command.commit(); command.waitUntilCompleted()
    guard command.status == .completed else { throw command.error ?? Failure.graphics }
    return output
  }

  private func prepareIdentity(logicalSize: CGSize, top: CGFloat, scale: CGFloat, width: Int, height: Int) throws {
    let ratio = min(1, 2048 / CGFloat(max(width, height)))
    let w = max(1, Int(CGFloat(width) * ratio)), h = max(1, Int(CGFloat(height) * ratio))
    let key = "\(w):\(h):\(logicalSize.width):\(logicalSize.height):\(contentRevision)"
    if rasterKey == key, identityTexture != nil { return }
    guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      let pixels = context.data else { throw Failure.graphics }
    context.translateBy(x: 0, y: CGFloat(h))
    context.scaleBy(x: CGFloat(w) / logicalSize.width, y: -CGFloat(h) / logicalSize.height)
    let side = 72 * scale
    let rect = CGRect(x: (logicalSize.width - side) / 2, y: top, width: side, height: side)
    let rounded = CGPath(roundedRect: rect, cornerWidth: side * 0.17, cornerHeight: side * 0.17, transform: nil)
    context.saveGState(); context.addPath(rounded); context.clip()
    context.setFillColor(CGColor(gray: 0.14, alpha: 1)); context.fill(rect)
    if let data = content?.artwork, let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 256,
        kCGImageSourceShouldCacheImmediately: true,
      ] as CFDictionary) {
      let cover = max(side / CGFloat(image.width), side / CGFloat(image.height))
      let imageRect = CGRect(x: rect.midX - CGFloat(image.width) * cover / 2,
        y: rect.midY - CGFloat(image.height) * cover / 2,
        width: CGFloat(image.width) * cover, height: CGFloat(image.height) * cover)
      context.translateBy(x: imageRect.minX, y: imageRect.maxY)
      context.scaleBy(x: 1, y: -1)
      context.draw(image, in: CGRect(origin: .zero, size: imageRect.size))
    } else {
      drawText("♪", context: context, centerX: rect.midX, top: rect.minY + side * 0.18,
        fontSize: side * 0.48, lineHeight: side * 0.65, maxWidth: side, gray: 0.78, bold: false)
    }
    context.restoreGState()
    context.addPath(rounded); context.setStrokeColor(CGColor(gray: 1, alpha: 0.7)); context.setLineWidth(1); context.strokePath()
    let textWidth = min(logicalSize.width - 40, 640)
    drawText(content?.title ?? "", context: context, centerX: logicalSize.width / 2,
      top: top + 89 * scale, fontSize: 19 * scale, lineHeight: 23.75 * scale,
      maxWidth: textWidth, gray: 0.965, bold: true)
    drawText(content?.artist ?? "", context: context, centerX: logicalSize.width / 2,
      top: top + 117.75 * scale, fontSize: 16 * scale, lineHeight: 20 * scale,
      maxWidth: textWidth, gray: 0.665, bold: false)
    let progress = CGRect(x: (logicalSize.width - textWidth * 0.8) / 2,
      y: top + 159.75 * scale, width: textWidth * 0.8, height: 2 * scale)
    context.setFillColor(CGColor(gray: 0.15, alpha: 1)); context.fill(progress)
    context.setFillColor(CGColor(gray: 0.835, alpha: 1)); context.fill(CGRect(x: progress.minX,
      y: progress.minY, width: progress.width * 0.24, height: progress.height))
    context.setFillColor(CGColor(gray: 0.945, alpha: 1)); context.fillEllipse(in: CGRect(
      x: progress.minX + progress.width * 0.24 - 3 * scale, y: progress.midY - 3 * scale,
      width: 6 * scale, height: 6 * scale))
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
      width: w, height: h, mipmapped: false)
    descriptor.usage = .shaderRead; descriptor.storageMode = .shared
    guard let texture = device.makeTexture(descriptor: descriptor) else { throw Failure.graphics }
    texture.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
      withBytes: pixels, bytesPerRow: w * 4)
    identityTexture = texture; rasterKey = key; identityRasterCount += 1
  }

  private func drawText(_ value: String, context: CGContext, centerX: CGFloat, top: CGFloat,
      fontSize: CGFloat, lineHeight: CGFloat, maxWidth: CGFloat, gray: CGFloat, bold: Bool) {
    guard !value.isEmpty else { return }
    let system = CTFontCreateUIFontForLanguage(.system, fontSize, nil)
      ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
    let font = bold ? CTFontCreateCopyWithAttributes(system, fontSize, nil,
      CTFontDescriptorCreateWithAttributes([kCTFontTraitsAttribute: [kCTFontWeightTrait: 0.23]] as CFDictionary)) : system
    let attributes: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): font,
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: gray, alpha: 1),
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attributes))
    let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
    let visible = CTLineGetTypographicBounds(line, nil, nil, nil) > maxWidth
      ? CTLineCreateTruncatedLine(line, Double(maxWidth), .end, token) ?? token : line
    let width = CGFloat(CTLineGetTypographicBounds(visible, nil, nil, nil))
    let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
    context.saveGState(); context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    context.textPosition = CGPoint(x: centerX - width / 2, y: top + (lineHeight - ascent - descent) / 2 + ascent)
    CTLineDraw(visible, context); context.restoreGState()
  }

  private static func tones(_ argb: UInt32) -> (SIMD3<Float>, SIMD3<Float>) {
    let r = Float((argb >> 16) & 255) / 255, g = Float((argb >> 8) & 255) / 255, b = Float(argb & 255) / 255
    let high = max(r, max(g, b)), low = min(r, min(g, b)), delta = high - low
    var hue: Float = 0
    if delta > 0 {
      if high == r { hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
      else if high == g { hue = (b - r) / delta + 2 }
      else { hue = (r - g) / delta + 4 }
      hue *= 60; if hue < 0 { hue += 360 }
    }
    func color(_ hue: Float) -> SIMD3<Float> {
      let h = hue / 60, chroma: Float = (1 - abs(2 * 0.58 - 1)) * 0.8
      let x = chroma * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)), m: Float = 0.58 - chroma / 2
      let v: SIMD3<Float>
      switch Int(h) { case 0: v = [chroma,x,0]; case 1: v = [x,chroma,0]; case 2: v = [0,chroma,x]
      case 3: v = [0,x,chroma]; case 4: v = [x,0,chroma]; default: v = [chroma,0,x] }
      return v + SIMD3<Float>(repeating: m)
    }
    return (color(hue), color((hue + 38).truncatingRemainder(dividingBy: 360)))
  }

  private enum Failure: Error { case graphics, dimensions }
  private static let source = """
  #include <metal_stdlib>
  using namespace metal;
  struct SongVertex { float4 position [[position]]; float2 uv; };
  vertex SongVertex songStripVertex(uint id [[vertex_id]]) {
    const float2 p[] = {float2(-1,1),float2(1,1),float2(-1,-1),float2(1,-1)};
    const float2 uv[] = {float2(0,0),float2(1,0),float2(0,1),float2(1,1)};
    return {float4(p[id],0,1),uv[id]};
  }
  float rounded(float2 p, float2 center, float2 halfSize, float radius, float aa) {
    float2 q=abs(p-center)-halfSize+radius;
    float d=length(max(q,0.0))+min(max(q.x,q.y),0.0)-radius;
    return 1.0-smoothstep(-aa,aa,d);
  }
  float3 ramp(float t) {
    return t<=0.55 ? mix(float3(1,0.843137,0.356863),float3(1,0.360784,0.611765),t/0.55)
      : mix(float3(1,0.360784,0.611765),float3(0.517647,0.227451,1),(t-0.55)/0.45);
  }
  float3 insideTone(float3 c) {
    float high=max(c.r,max(c.g,c.b)),low=min(c.r,min(c.g,c.b));
    float light=(high+low)*0.5;
    float sat=(high-low)/(1.0-abs(2.0*light-1.0));
    float hue=0,delta=high-low;
    if(delta>0){ if(high==c.r)hue=fmod((c.g-c.b)/delta+6.0,6.0);
      else if(high==c.g)hue=(c.b-c.r)/delta+2.0; else hue=(c.r-c.g)/delta+4.0; }
    float chroma=0.9*sat,x=chroma*(1.0-abs(fmod(hue,2.0)-1.0));
    float3 v=hue<1?float3(chroma,x,0):hue<2?float3(x,chroma,0):hue<3?float3(0,chroma,x)
      :hue<4?float3(0,x,chroma):hue<5?float3(x,0,chroma):float3(chroma,0,x);
    return v+(0.45-chroma*0.5);
  }
  fragment float4 songStripFragment(SongVertex in [[stage_in]], constant float* u [[buffer(0)]],
      texture2d<float> identity [[texture(0)]]) {
    constexpr sampler s(coord::normalized,filter::linear,address::clamp_to_edge);
    float2 p=in.uv*float2(u[0],u[1]); float scale=u[2],side=72*scale;
    float pulse=u[5],energy=u[6],strength=clamp(energy*0.68+pulse*0.32,0.0,1.0);
    float3 color=float3(0); float2 artCenter=float2(u[0]*0.5,u[3]+side*0.5);
    float radius=side*1.2*(0.92+energy*0.12+pulse*0.10);
    for(int i=0;i<2;i++){
      float2 center=artCenter+float2((i==0?-0.36:0.36)*side,0);
      float t=distance(p,center)/max(radius,0.001);
      float a=t<0.45?mix(0.58,0.24,t/0.45):mix(0.24,0.0,clamp((t-0.45)/0.55,0.0,1.0));
      float3 tone=i==0?float3(u[52],u[53],u[54]):float3(u[55],u[56],u[57]);
      color=mix(color,tone,a*strength);
    }
    float4 text=identity.sample(s,in.uv); color=text.rgb+color*(1-text.a);
    float2 center=float2(u[0]*0.5,u[4]); float width=min(u[0]*0.4,330.0),height=min(60*scale,76.0);
    float aa=max(fwidth(p.x),fwidth(p.y))*0.65;
    float2 halfSize=float2(width,height)*0.5; float corner=height*0.13;
    float outer=rounded(p,center,halfSize,corner,aa),border=3.5+pulse*1.8;
    float inner=rounded(p,center,halfSize-border,max(corner-border,0.0),aa);
    float gradientT=clamp((p.x-center.x+width*0.5)/width,0.0,1.0);
    for(int n=3;n>0;n--){
      float outline=rounded(p,center,halfSize+float(n)*1.7+1,corner+float(n)*1.7+1,aa)
        -rounded(p,center,halfSize+float(n)*1.7-1,corner+float(n)*1.7-1,aa);
      color=mix(color,ramp(gradientT),max(outline,0.0)*(0.015+pulse*0.035));
    }
    color=mix(color,ramp(gradientT),outer);
    color=mix(color,float3(0.949020,0.956863,0.949020),inner);
    float step=u[0]/45.0,barWidth=clamp(step*0.37,2.0,6.0);
    int index=clamp(int(p.x/step),0,44); float value=u[7+index];
    bool selected=index==22; float bw=barWidth*(selected?1.2:1.0);
    float bh=height*((index%2==0?0.24:0.13)+value*0.57);
    float coverage=rounded(p,float2(step*(float(index)+0.5),center.y),float2(bw,bh)*0.5,bw*0.5,aa);
    float3 barColor=ramp(float(index)/44.0);
    float3 inside=mix(float3(0.768627,0.784314,0.803922),insideTone(barColor),0.60+value*0.40);
    if(selected){float t=clamp((p.y-center.y+height*0.5)/height,0.0,1.0);
      inside=t<=0.5?mix(float3(0.517647,0.227451,1),float3(1,0.360784,0.611765),t*2)
        :mix(float3(1,0.360784,0.611765),float3(1,0.843137,0.356863),(t-0.5)*2);}
    color=mix(color,barColor,coverage*(1-outer)*(0.38+value*0.62));
    color=mix(color,inside,coverage*inner);
    return float4(color,1);
  }
  """
}
