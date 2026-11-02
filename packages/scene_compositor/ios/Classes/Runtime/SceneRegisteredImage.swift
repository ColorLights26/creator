import Foundation
import CoreGraphics
import CoreImage
import CoreText
import ImageIO
import Metal
import MetalKit
import simd

struct SceneRegisteredImageViewport: Equatable {
  let fit: String
  let alignX: Double
  let alignY: Double
  let extendEdges: Bool
  let edgeFadeExtent: Double

  static func parse(_ raw: Any) -> Self? {
    guard let value = raw as? [String: Any],
      Set(value.keys) == ["fit", "alignX", "alignY", "extendEdges", "edgeFadeExtent"],
      let fit = value["fit"] as? String, ["cover", "contain"].contains(fit),
      let x = registeredImageNumber(value["alignX"], -1, 1),
      let y = registeredImageNumber(value["alignY"], -1, 1),
      let flag = value["extendEdges"] as? NSNumber, CFGetTypeID(flag) == CFBooleanGetTypeID(),
      let fade = registeredImageNumber(value["edgeFadeExtent"], 0, 500)
    else { return nil }
    return Self(fit: fit, alignX: x, alignY: y, extendEdges: flag.boolValue, edgeFadeExtent: fade)
  }

  func imageRect(source: CGSize, viewport: CGSize) -> CGRect {
    let x = viewport.width / source.width, y = viewport.height / source.height
    let scale = fit == "contain" ? min(x, y) : max(x, y)
    let width = source.width * scale, height = source.height * scale
    return CGRect(x: (viewport.width - width) * (alignX + 1) * 0.5,
      y: (viewport.height - height) * (alignY + 1) * 0.5, width: width, height: height)
  }

  static let cover = Self(fit: "cover", alignX: 0, alignY: 0, extendEdges: false, edgeFadeExtent: 0)
}

struct SceneRegisteredImageResponse: Equatable {
  let attackSeconds: Double
  let releaseSeconds: Double
  let idleGain: Double
  let sustainGain: Double
  let beatGain: Double
  let reflectionIdleGain: Double
  let reflectionResponseGain: Double

  static let standard = Self(attackSeconds: 0.28, releaseSeconds: 1.2,
    idleGain: 0.42, sustainGain: 0.30, beatGain: 1.25,
    reflectionIdleGain: 0.80, reflectionResponseGain: 0.28)

  static func parse(_ raw: Any) -> Self? {
    guard let value = raw as? [String: Any],
      Set(value.keys) == ["attackSeconds", "releaseSeconds", "idleGain", "sustainGain",
        "beatGain", "reflectionIdleGain", "reflectionResponseGain"],
      let attack = registeredImageNumber(value["attackSeconds"], 0.001, 5),
      let release = registeredImageNumber(value["releaseSeconds"], 0.001, 5),
      let idle = registeredImageNumber(value["idleGain"], 0, 1),
      let sustain = registeredImageNumber(value["sustainGain"], 0, 2),
      let beat = registeredImageNumber(value["beatGain"], 0, 3),
      let reflectionIdle = registeredImageNumber(value["reflectionIdleGain"], 0, 1),
      let reflectionResponse = registeredImageNumber(value["reflectionResponseGain"], 0, 1)
    else { return nil }
    return Self(attackSeconds: attack, releaseSeconds: release, idleGain: idle,
      sustainGain: sustain, beatGain: beat, reflectionIdleGain: reflectionIdle,
      reflectionResponseGain: reflectionResponse)
  }
}

private func registeredImageNumber(_ value: Any?, _ low: Double, _ high: Double) -> Double? {
  guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
    value.doubleValue.isFinite, (low...high).contains(value.doubleValue) else { return nil }
  return value.doubleValue
}

struct SceneRegisteredImageConfiguration {
  let coverage: CIImage
  let haloStrength: Double
  let layout: String
  let placeholderProgress: Double
  var contentScale: Double = 1
  var viewport: SceneRegisteredImageViewport? = nil
  var response: SceneRegisteredImageResponse? = nil
}

/// An installed photographic component of the existing scene. It owns static
/// textures and bounded envelopes, but no scene clock, sensor or display link.
@available(iOS 15.0, *)
final class SceneRegisteredImageProgram {
  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let pipeline: MTLRenderPipelineState
  private let source: MTLTexture
  private let coverage: MTLTexture
  private let corners: [SIMD2<Double>]
  private let configuration: SceneRegisteredImageConfiguration
  private let background: UInt32
  private let primary: UInt32
  private let idleAccent: SIMD3<Float>
  private var accent: SIMD3<Float>
  private var fromAccent: SIMD3<Float>
  private var targetAccent: SIMD3<Float>
  private var colorAge = 0.7
  private var content: SceneCatalogSongContent?
  private var panel: MTLTexture?
  private var artwork: CGImage?
  private var providerMark: CGImage?
  private var playbackAnchor: Double?
  private var playbackPosition = 0.0
  private var panelSecond = -1
  private(set) var panelRasterCount = 0
  private var frame: SceneRenderSignalFrameV2?
  private var session: Int64 = -1
  private var serials: [Int64] = [0,0,0,0]
  private var pending: Float = 0
  private var peak: Float = 0
  private var pulse: Float = 0
  private var energy: Float = 0
  private var attackRemaining = 0.0
  private var haloAge = 10.0
  private var lastTrigger = -10.0
  private var previousHost: Double?
  private var playing = false
  private(set) var halo: Float = 0
  private(set) var haloRadius: Float = 0

  init(device: MTLDevice, source: CIImage, configuration: SceneRegisteredImageConfiguration,
       corners: [SIMD2<Double>], background: UInt32, primary: UInt32, accent: UInt32) throws {
    guard let queue = device.makeCommandQueue(), let original = source.cgImage,
      let mask = configuration.coverage.cgImage, corners.count == 4,
      original.width == mask.width, original.height == mask.height else { throw Failure.resources }
    self.device = device; self.queue = queue; self.configuration = configuration
    self.corners = corners; self.background = background; self.primary = primary
    idleAccent = Self.rgb(accent); self.accent = Self.rgb(accent)
    fromAccent = Self.rgb(accent); targetAccent = Self.rgb(accent)
    let loader = MTKTextureLoader(device: device)
    let options: [MTKTextureLoader.Option: Any] = [.SRGB:false, .origin:MTKTextureLoader.Origin.topLeft,
      .textureUsage:NSNumber(value: MTLTextureUsage.shaderRead.rawValue)]
    self.source = try loader.newTexture(cgImage: original, options: options)
    coverage = try loader.newTexture(cgImage: mask, options: options)
    let library = try device.makeLibrary(source: Self.shader, options: nil)
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = library.makeFunction(name: "registeredVertex")
    descriptor.fragmentFunction = library.makeFunction(name: "registeredFragment")
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
  }

  private var usesObservedPlayback: Bool { configuration.viewport != nil || configuration.layout == "dashboard" }
  var needsFrames: Bool { playing && ((usesObservedPlayback && content?.playback?.playing == true) || pending > 0 || pulse > 0 || energy > 0 ||
    (peak > 0 && haloAge < 5) || colorAge < 0.7 || frame.map { $0.available && $0.fresh && $0.musicActive } == true) }

  @discardableResult
  func updateSongContent(_ next: SceneCatalogSongContent?) -> Bool {
    guard next != content else { return false }
    if next?.artwork != content?.artwork || next?.artworkBrightness != content?.artworkBrightness ||
      next?.artworkSaturation != content?.artworkSaturation || next?.artworkOpacity != content?.artworkOpacity {
      artwork = next?.resolvedArtwork(maximumPixelSize: 1024)
    }
    if next?.providerMark != content?.providerMark { providerMark = next?.resolvedProviderMark() }
    content = next; panel = nil; playbackAnchor = nil; panelSecond = -1
    fromAccent = accent
    targetAccent = next?.artwork != nil ? Self.rgb(next!.accent) : idleAccent
    colorAge = 0
    return true
  }

  @discardableResult
  func consume(_ next: SceneRenderSignalFrameV2) -> Bool {
    let newSession = session != next.sessionId
    if newSession { clearMotion(); session = next.sessionId }
    let events = [next.beat, next.accent, next.impact, next.flash]
    if next.available && next.fresh && next.musicActive && !newSession {
      if next.usesMappedMusicAuthority {
        if (next.beat.active && next.beat.serial > serials[0]) || mappedBeatCrossed(next) { pending = max(pending, 0.75 + 0.25 * unit(next.dynamics[2])) }
      } else {
        let floors: [Float] = [0.65,0.60,0.55,0]
        for i in events.indices where events[i].active && events[i].serial != serials[i] {
          pending = max(pending, floors[i] + (1-floors[i]) * unit(events[i].strength))
        }
      }
    }
    serials = events.map(\.serial); frame = next
    return true
  }

  func setPlaying(_ next: Bool, hostTime: Double) {
    if usesObservedPlayback && next != playing { panel = nil }
    if usesObservedPlayback, playing, !next, let snapshot = content?.playback, snapshot.playing,
      let anchor = playbackAnchor { playbackPosition = min(snapshot.durationSeconds, snapshot.positionSeconds + max(0, hostTime-anchor)) }
    playing = next; previousHost = hostTime
    if next, let snapshot = content?.playback {
      playbackAnchor = hostTime - max(0, playbackPosition-snapshot.positionSeconds)
    }
    if !next { clearMotion(); frame = nil }
  }

  private func mappedBeatCrossed(_ next: SceneRenderSignalFrameV2) -> Bool {
    guard let previous = frame, previous.usesMappedMusicAuthority,
      previous.available, previous.fresh, previous.musicActive,
      next.audioTimestampMicros > previous.audioTimestampMicros,
      next.audioTimestampMicros - previous.audioTimestampMicros <= 250_000 else { return false }
    return unit(previous.rhythm[1])-unit(next.rhythm[1]) > 0.5
  }

  func advance(hostTime: Double, reducedMotion: Bool) {
    guard hostTime.isFinite else { clearMotion(); return }
    let dt = min(0.1, max(0, previousHost.map { hostTime-$0 } ?? 1/30))
    previousHost = hostTime
    colorAge = min(0.7, colorAge+dt)
    let t = Float(colorAge/0.7), eased = t*t*(3-2*t)
    accent = fromAccent + (targetAccent-fromAccent)*eased
    guard playing, !reducedMotion else { clearMotion(); return }
    if pending > 0 && hostTime-lastTrigger >= 0.18 {
      peak = pending; attackRemaining = 0.035; haloAge = 0; lastTrigger = hostTime
    }
    pending = 0; haloAge = min(10, haloAge+dt)
    if attackRemaining > 0 { pulse += (peak-pulse)*Float(1-exp(-dt/0.012)); attackRemaining -= dt }
    else { pulse *= Float(exp(-dt/0.30)) }
    if pulse < 0.0001 { pulse = 0 }
    var target: Float = 0
    if let frame, frame.available && frame.fresh && frame.musicActive {
      target = frame.usesMappedMusicAuthority ? unit(frame.dynamics[2])*0.80 :
        unit(frame.channels[1])*0.38 + unit(frame.channels[3])*0.32 + unit(frame.channels[0])*0.20 + unit(frame.dynamics[2])*0.10
    }
    let response = configuration.response ?? .standard
    energy += (target-energy)*Float(1-exp(-dt/(target > energy ? response.attackSeconds : response.releaseSeconds)))
    if target == 0 && energy < 0.0001 { energy = 0 }
    halo = haloAge > 5 ? 0 : peak * Float((1-exp(-haloAge/0.035))*exp(-haloAge/0.70))
    haloRadius = Float(min(1, haloAge/0.42))
  }

  private func clearMotion() {
    pending = 0; peak = 0; pulse = 0; energy = 0; halo = 0; haloRadius = 0
    haloAge = 10; attackRemaining = 0; lastTrigger = -10
  }
  private func unit(_ n: Float) -> Float { n.isFinite ? min(1,max(0,n)) : 0 }

  func render(width: Int, height: Int, hostTime: Double, reducedMotion: Bool,
              outputAllocator: SceneSurfaceNativeOutputAllocator?, logicalSize: CGSize? = nil) throws -> MTLTexture {
    advance(hostTime: hostTime, reducedMotion: reducedMotion)
    if usesObservedPlayback, let snapshot = content?.playback {
      if playbackAnchor == nil { playbackAnchor = hostTime; playbackPosition = snapshot.positionSeconds }
      if playing && snapshot.playing {
        playbackPosition = min(snapshot.durationSeconds, snapshot.positionSeconds + max(0, hostTime-playbackAnchor!))
      } else if !snapshot.playing { playbackPosition = snapshot.positionSeconds }
      let second = Int(playbackPosition)
      if second != panelSecond { panel = nil; panelSecond = second }
    }
    if panel == nil { panel = try rasterPanel() }
    guard let panel, let output = try SceneSurfaceNativeOutputAllocator.makeTexture(device: device,
      width: width, height: height, allocator: outputAllocator), let command = queue.makeCommandBuffer() else { throw Failure.graphics }
    let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = output
    pass.colorAttachments[0].loadAction = .dontCare; pass.colorAttachments[0].storeAction = .store
    guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw Failure.graphics }
    let response = configuration.response ?? .standard
    let gain = Float(response.idleGain) + energy*Float(response.sustainGain) + pulse*Float(response.beatGain)
    let reflection = Float(response.reflectionIdleGain) + Float(response.reflectionResponseGain)*max(gain-Float(response.idleGain), 0)
    let viewport = configuration.viewport ?? .cover
    let rect = viewport.imageRect(source: CGSize(width: source.width, height: source.height),
      viewport: CGSize(width: width, height: height))
    let logicalScale = logicalSize.map { $0.width > 0 ? Double(width)/$0.width : 1 } ?? 1
    let placement: [Float] = [Float(rect.minX/Double(width)), Float(rect.minY/Double(height)),
      Float(rect.width/Double(width)), Float(rect.height/Double(height)),
      viewport.extendEdges ? 1 : 0, Float(viewport.edgeFadeExtent*logicalScale), reflection]
    let uniforms: [Float] = [Float(width),Float(height),Float(source.width),Float(source.height),
      gain, halo*Float(configuration.haloStrength),haloRadius,
      accent.x,accent.y,accent.z] + (try Self.inverseHomography(corners)) + placement
    encoder.setRenderPipelineState(pipeline)
    uniforms.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length:$0.count, index:0) }
    encoder.setFragmentTexture(source,index:0); encoder.setFragmentTexture(coverage,index:1); encoder.setFragmentTexture(panel,index:2)
    encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:6); encoder.endEncoding()
    command.commit(); command.waitUntilCompleted()
    guard command.status == .completed else { throw command.error ?? Failure.graphics }
    return output
  }

  private func rasterPanel() throws -> MTLTexture {
    let dimensions = Self.panelSize(source: CGSize(width: source.width, height: source.height),
      corners: corners, preserveLegacy: !usesObservedPlayback)
    let w = Int(dimensions.width), h = Int(dimensions.height)
    guard let ctx = CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,
      space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Failure.graphics }
    ctx.translateBy(x:0,y:CGFloat(h)); ctx.scaleBy(x:1,y:-1)
    let bounds = CGRect(x:0,y:0,width:w,height:h)
    ctx.setFillColor(Self.color(background)); ctx.fill(bounds)
    if usesObservedPlayback {
      if configuration.layout == "dashboard" { try drawDashboard(bounds: bounds, context: ctx) }
      else { try drawPlayer(bounds: bounds, context: ctx) }
      guard let image = ctx.makeImage() else { throw Failure.graphics }
      panelRasterCount += 1
      return try MTKTextureLoader(device:device).newTexture(cgImage:image,options:[.SRGB:false,.origin:MTKTextureLoader.Origin.topLeft])
    }
    let artwork = self.artwork
    let immersive = configuration.layout == "immersive"
    let unit = CGFloat(h), padding = unit*0.11, side = unit*0.78
    let right = configuration.layout == "artworkRight"
    let art = immersive ? bounds : CGRect(x:right ? CGFloat(w)-padding-side : padding,y:padding,width:side,height:side)
    if let artwork {
      ctx.saveGState(); ctx.addPath(CGPath(roundedRect:art,cornerWidth:side*0.05,cornerHeight:side*0.05,transform:nil)); ctx.clip()
      let scale = max(art.width/CGFloat(artwork.width),art.height/CGFloat(artwork.height))
      let size = CGSize(width:CGFloat(artwork.width)*scale,height:CGFloat(artwork.height)*scale)
      ctx.translateBy(x:art.midX-size.width/2,y:art.midY+size.height/2); ctx.scaleBy(x:1,y:-1)
      ctx.draw(artwork,in:CGRect(origin:.zero,size:size)); ctx.restoreGState()
    } else {
      ctx.setFillColor(CGColor(red:CGFloat(accent.x)*0.25,green:CGFloat(accent.y)*0.25,blue:CGFloat(accent.z)*0.25,alpha:1)); ctx.fill(art)
      text("♪", rect:art.insetBy(dx:art.width*0.32,dy:art.height*0.28), size:art.height*0.35, color:0xfff5f5f5, context:ctx)
    }
    let details: CGRect
    if immersive {
      ctx.setFillColor(CGColor(gray:0,alpha:0.60)); ctx.fill(CGRect(x:0,y:unit*0.45,width:CGFloat(w),height:unit*0.55))
      details = CGRect(x:CGFloat(w)*0.2,y:unit*0.53,width:CGFloat(w)*0.6,height:unit*0.43)
    } else {
      details = CGRect(x:right ? padding : padding*1.9+side,y:padding,
        width:CGFloat(w)-side-padding*2.9,height:unit-padding*2)
    }
    let ink: UInt32 = immersive ? 0xfffaf3ff : primary
    let fontUnit = (immersive ? unit*0.50 : unit)*configuration.contentScale
    var y = details.minY + details.height*0.13
    if let content {
      y += text(content.title,rect:CGRect(x:details.minX,y:y,width:details.width,height:fontUnit*0.30),size:fontUnit*0.13,color:ink,context:ctx,maxLines:2) + fontUnit*0.025
      text(content.artist,rect:CGRect(x:details.minX,y:y,width:details.width,height:fontUnit*0.14),size:fontUnit*0.095,color:ink,context:ctx)
      y += fontUnit*0.19
    } else { y += fontUnit*0.23 }
    let bar = CGRect(x:details.minX,y:y,width:details.width,height:max(3,fontUnit*0.022))
    ctx.setFillColor(Self.color(ink, alpha:0.18)); ctx.fill(bar)
    ctx.setFillColor(Self.color(ink, alpha:0.85)); ctx.fill(CGRect(x:bar.minX,y:bar.minY,width:bar.width*configuration.placeholderProgress,height:bar.height))
    let cy = y+fontUnit*0.14, icon = fontUnit*0.075
    for i in 0..<4 {
      let cx = details.minX+details.width*(CGFloat(i)+0.5)/4
      ctx.setFillColor(Self.color(ink,alpha:0.85))
      if i == 0 {
        ctx.setStrokeColor(Self.color(ink,alpha:0.85)); ctx.setLineWidth(max(1.5,icon*0.10)); ctx.setLineCap(.round)
        for sign:CGFloat in [-1,1] {
          ctx.move(to:CGPoint(x:cx-icon*0.45,y:cy-sign*icon*0.30))
          ctx.addCurve(to:CGPoint(x:cx+icon*0.42,y:cy+sign*icon*0.30),control1:CGPoint(x:cx,y:cy-sign*icon*0.30),control2:CGPoint(x:cx,y:cy+sign*icon*0.30))
          ctx.strokePath()
          ctx.move(to:CGPoint(x:cx+icon*0.24,y:cy+sign*icon*0.11)); ctx.addLine(to:CGPoint(x:cx+icon*0.43,y:cy+sign*icon*0.30)); ctx.addLine(to:CGPoint(x:cx+icon*0.24,y:cy+sign*icon*0.48)); ctx.strokePath()
        }
      } else if i == 2 && content != nil {
        ctx.fill(CGRect(x:cx-icon*0.42,y:cy-icon/2,width:icon*0.25,height:icon)); ctx.fill(CGRect(x:cx+icon*0.17,y:cy-icon/2,width:icon*0.25,height:icon))
      } else {
        let sign:CGFloat = i == 1 ? -1:1
        let p=CGMutablePath(); p.move(to:CGPoint(x:cx-sign*icon*0.40,y:cy-icon/2)); p.addLine(to:CGPoint(x:cx+sign*icon*0.40,y:cy)); p.addLine(to:CGPoint(x:cx-sign*icon*0.40,y:cy+icon/2)); p.closeSubpath(); ctx.addPath(p); ctx.fillPath()
        if i == 1 || i == 3 { ctx.fill(CGRect(x:cx+sign*icon*0.44-icon*0.08,y:cy-icon/2,width:icon*0.16,height:icon)) }
      }
    }
    guard let image = ctx.makeImage() else { throw Failure.graphics }
    panelRasterCount += 1
    return try MTKTextureLoader(device:device).newTexture(cgImage:image,options:[.SRGB:false,.origin:MTKTextureLoader.Origin.topLeft])
  }

  /// Measure edges in source pixels, not normalized UV distance. One flat
  /// texture is projected once, so text and covers cannot bend independently.
  static func panelSize(source: CGSize, corners: [SIMD2<Double>], preserveLegacy: Bool = false) -> CGSize {
    if preserveLegacy {
      let ratio = max(1, simd_distance(corners[0], corners[1])*Double(source.width) /
        max(1,simd_distance(corners[0], corners[3])*Double(source.height)))
      return CGSize(width: 1024, height: max(256, min(768, Int(1024/ratio))))
    }
    let pixels = corners.map { SIMD2($0.x*Double(source.width), $0.y*Double(source.height)) }
    let horizontal = (simd_distance(pixels[0], pixels[1])+simd_distance(pixels[3], pixels[2]))/2
    let vertical = (simd_distance(pixels[0], pixels[3])+simd_distance(pixels[1], pixels[2]))/2
    let ratio = horizontal/max(1, vertical)
    return ratio >= 1 ? CGSize(width: 1024, height: max(128, Int(1024/ratio))) :
      CGSize(width: max(128, Int(1024*ratio)), height: 1024)
  }

  private func drawArtwork(in rect: CGRect, radius: CGFloat, context: CGContext) throws {
    if let artwork { SceneSongPanelDrawing.image(artwork, in: rect, radius: radius, context: context) }
    else {
      context.setFillColor(Self.color(background)); context.fill(rect)
      try SceneSongPanelDrawing.icon("music.note", rect: rect.insetBy(dx: rect.width*0.3, dy: rect.height*0.3), color: primary, context: context)
    }
  }

  private func drawDashboard(bounds: CGRect, context c: CGContext) throws {
    let scale = min(bounds.width/768, bounds.height/360)
    c.saveGState(); defer { c.restoreGState() }
    c.translateBy(x: (bounds.width-768*scale)/2, y: (bounds.height-360*scale)/2); c.scaleBy(x: scale, y: scale)
    let draw = SceneSongPanelDrawing.self
    c.setFillColor(draw.color(0xff222125))
    c.addPath(CGPath(roundedRect: CGRect(x: 14,y: 13,width: 56,height: 333), cornerWidth: 9,cornerHeight: 9,transform:nil)); c.fillPath()
    try draw.icon("square.grid.2x2", rect: CGRect(x:28,y:31,width:28,height:28),color:primary,context:c)
    for (y, name) in [(87.0,"map.fill"), (203.0,"phone.fill")] {
      let rect=CGRect(x:24,y:y,width:36,height:36)
      c.setFillColor(draw.color(0xff37ba62)); c.addPath(CGPath(roundedRect:rect,cornerWidth:8,cornerHeight:8,transform:nil)); c.fillPath()
      try draw.icon(name,rect:rect.insetBy(dx:6,dy:6),color:0xffffffff,context:c)
    }
    let sourceRect=CGRect(x:24,y:145,width:36,height:36)
    if let providerMark { draw.image(providerMark,in:sourceRect,radius:7,context:c,fit:true) }
    else { try draw.icon("music.note",rect:sourceRect.insetBy(dx:5,dy:5),color:primary,context:c) }
    try draw.icon("mic.fill",rect:CGRect(x:30,y:266,width:24,height:24),color:primary,context:c)
    try draw.icon("circle.grid.3x3.fill",rect:CGRect(x:26,y:309,width:32,height:32),color:primary,context:c)
    try draw.icon("chevron.backward.circle.fill",rect:CGRect(x:94,y:29,width:30,height:30),color:primary,context:c)
    draw.text(content?.providerName ?? "",rect:CGRect(x:445,y:35,width:282,height:31),size:22,color:primary,context:c,alpha:0.65)
    draw.text(content?.title ?? "",rect:CGRect(x:97,y:96,width:305,height:46),size:31,color:primary,context:c,medium:true)
    draw.text(content?.artist ?? "",rect:CGRect(x:97,y:144,width:305,height:31),size:23,color:primary,context:c,alpha:0.78)
    if let providerMark {
      draw.image(providerMark,in:CGRect(x:97,y:179,width:25,height:25),radius:3,context:c,fit:true)
      draw.text(content?.providerName ?? "",rect:CGRect(x:131,y:179,width:271,height:29),size:19,color:primary,context:c,alpha:0.65)
    }
    try drawArtwork(in:CGRect(x:444,y:79,width:268,height:268),radius:7,context:c)
    let isPlaying = playing && (content?.playback?.playing ?? (content?.artworkOnly == false))
    for (i,name) in ["backward.end.fill",isPlaying ? "pause.fill":"play.fill","forward.end.fill"].enumerated() {
      try draw.icon(name,rect:CGRect(x:100+(CGFloat(i)+0.5)*95-18,y:221,width:36,height:36),color:primary,context:c)
    }
    let bar=CGRect(x:152,y:288,width:175,height:4)
    c.setFillColor(draw.color(primary,alpha:0.20)); c.fill(bar)
    if let snapshot=content?.playback {
      c.setFillColor(draw.color(content?.accent ?? primary)); c.fill(CGRect(x:bar.minX,y:bar.minY,width:bar.width*playbackPosition/snapshot.durationSeconds,height:bar.height))
      draw.text(draw.clock(playbackPosition),rect:CGRect(x:100,y:278,width:44,height:24),size:17,color:primary,context:c,alpha:0.75)
      draw.text(draw.clock(snapshot.durationSeconds),rect:CGRect(x:333,y:278,width:52,height:24),size:17,color:primary,context:c,alpha:0.75,right:true)
    }
    for (i,name) in ["heart","shuffle","message","dot.radiowaves.left.and.right"].enumerated() {
      try draw.icon(name,rect:CGRect(x:100+(CGFloat(i)+0.5)*71.25-12.5,y:325,width:25,height:26),color:primary,context:c)
    }
  }

  private func drawPlayer(bounds: CGRect, context c: CGContext) throws {
    let wide = bounds.width >= bounds.height*1.4
    let unit = min(bounds.width, bounds.height*0.7)
    let pad=unit*0.09
    let side=min(bounds.width-2*pad,bounds.height*(wide ? 0.82:0.55))
    let art=CGRect(x:wide ? pad:(bounds.width-side)/2,y:pad,width:side,height:side)
    try drawArtwork(in:art,radius:side*0.05,context:c)
    let details=wide ? CGRect(x:art.maxX+pad,y:pad,width:bounds.width-art.maxX-2*pad,height:bounds.height-2*pad) :
      CGRect(x:pad,y:art.maxY+pad,width:bounds.width-2*pad,height:bounds.height-art.maxY-2*pad)
    guard details.width > 0, details.height > 0 else { return }
    c.saveGState(); defer { c.restoreGState() }; c.clip(to:details)
    let draw=SceneSongPanelDrawing.self
    let fontUnit=unit*configuration.contentScale
    var y=details.minY
    y += draw.text(content?.title ?? "",rect:CGRect(x:details.minX,y:y,width:details.width,height:fontUnit*0.30),size:fontUnit*0.13,color:primary,context:c,maxLines:2,medium:true)
    y += draw.text(content?.artist ?? "",rect:CGRect(x:details.minX,y:y,width:details.width,height:fontUnit*0.14),size:fontUnit*0.095,color:content?.accent ?? primary,context:c,lineHeight:1.2)
    if let name=content?.providerName, !name.isEmpty {
      y += draw.text(name,rect:CGRect(x:details.minX,y:y,width:details.width,height:fontUnit*0.09),size:fontUnit*0.065,color:primary,context:c,lineHeight:1.3,alpha:0.65)
    }
    let gap=fontUnit*0.06, progressHeight=fontUnit*(content?.playback == nil ? 0.10:0.20)
    y += gap
    if y+progressHeight <= details.maxY {
      let real=content?.playback
      let bar=CGRect(x:details.minX,y:y+progressHeight*0.12,width:details.width,height:max(2,progressHeight*(real == nil ? 0.28:0.14)))
      c.setFillColor(draw.color(primary,alpha:0.18)); c.fill(bar)
      let progress=real.map { playbackPosition/$0.durationSeconds } ?? configuration.placeholderProgress
      c.setFillColor(draw.color(content?.accent ?? primary)); c.fill(CGRect(x:bar.minX,y:bar.minY,width:bar.width*progress,height:bar.height))
      if let real {
        let rect=CGRect(x:details.minX,y:bar.maxY+progressHeight*0.14,width:details.width,height:progressHeight*0.5)
        draw.text(draw.clock(playbackPosition),rect:rect,size:progressHeight*0.32,color:primary,context:c,alpha:0.6)
        draw.text(draw.clock(real.durationSeconds),rect:rect,size:progressHeight*0.32,color:primary,context:c,alpha:0.6,right:true)
      }
      y += progressHeight
    }
    let controls=fontUnit*0.12
    if y+controls <= details.maxY {
      let isPlaying=playing && (content?.playback?.playing ?? (content?.artworkOnly == false))
      let names=["shuffle","backward.end.fill",isPlaying ? "pause.fill":"play.fill","forward.end.fill"]
      let count=providerMark == nil ? 4:5, slot=details.width/CGFloat(count), icon=controls*0.9
      for (i,name) in names.enumerated() {
        try draw.icon(name,rect:CGRect(x:details.minX+(CGFloat(i)+0.5)*slot-icon/2,y:y,width:icon,height:controls),color:i == 0 ? content?.accent ?? primary:primary,context:c,alpha:i == 0 ? 1:0.85)
      }
      if let providerMark { draw.image(providerMark,in:CGRect(x:details.minX+4.5*slot-icon/2,y:y,width:icon,height:controls),radius:2,context:c,fit:true) }
    }
  }

  @discardableResult
  private func text(_ value:String, rect:CGRect, size:CGFloat, color:UInt32, context:CGContext, maxLines:Int=1) -> CGFloat {
    guard !value.isEmpty else { return 0 }
    let font=CTFontCreateWithName("HelveticaNeue" as CFString,size,nil)
    let attributed=NSAttributedString(string:value,attributes:[NSAttributedString.Key(kCTFontAttributeName as String):font,NSAttributedString.Key(kCTForegroundColorAttributeName as String):Self.color(color)])
    let typesetter=CTTypesetterCreateWithAttributedString(attributed)
    let ellipsis=CTLineCreateWithAttributedString(NSAttributedString(string:"…",attributes:attributed.attributes(at:0,effectiveRange:nil)))
    var offset=0, count=0
    while offset<attributed.length && count<maxLines {
      let length=max(1,CTTypesetterSuggestLineBreak(typesetter,offset,Double(rect.width)))
      let range=CFRange(location:offset,length:count == maxLines-1 ? attributed.length-offset:length)
      let line=CTTypesetterCreateLine(typesetter,range)
      let fitted=count == maxLines-1 ? CTLineCreateTruncatedLine(line,Double(rect.width),.end,ellipsis) ?? line:line
      context.saveGState(); context.clip(to:rect); context.translateBy(x:rect.minX,y:rect.minY+size+CGFloat(count)*size*1.15); context.scaleBy(x:1,y:-1); context.textPosition = .zero; CTLineDraw(fitted,context); context.restoreGState()
      offset += length; count += 1
    }
    return CGFloat(count)*size*1.15
  }
  private static func rgb(_ value:UInt32)->SIMD3<Float> { SIMD3(Float((value>>16)&255)/255,Float((value>>8)&255)/255,Float(value&255)/255) }
  private static func color(_ value:UInt32,alpha:CGFloat=1)->CGColor { let c=rgb(value); return CGColor(red:CGFloat(c.x),green:CGFloat(c.y),blue:CGFloat(c.z),alpha:alpha) }
  private static func inverseHomography(_ p:[SIMD2<Double>]) throws -> [Float] {
    let s=p[0]-p[1]+p[2]-p[3], d1=p[1]-p[2], d2=p[3]-p[2]
    let det=d1.x*d2.y-d2.x*d1.y
    var g=0.0,h=0.0
    if abs(s.x)+abs(s.y)>1e-10 { guard abs(det)>1e-10 else { throw Failure.resources }; g=(s.x*d2.y-d2.x*s.y)/det; h=(d1.x*s.y-s.x*d1.y)/det }
    let matrix=simd_double3x3(columns:(SIMD3(p[1].x-p[0].x+g*p[1].x,p[1].y-p[0].y+g*p[1].y,g),SIMD3(p[3].x-p[0].x+h*p[3].x,p[3].y-p[0].y+h*p[3].y,h),SIMD3(p[0].x,p[0].y,1)))
    guard abs(simd_determinant(matrix))>1e-10 else { throw Failure.resources }
    let m=simd_inverse(matrix)
    return [m[0].x,m[1].x,m[2].x,m[0].y,m[1].y,m[2].y,m[0].z,m[1].z,m[2].z].map(Float.init)
  }
  enum Failure:Error { case resources,graphics }
  private static let shader = """
  #include <metal_stdlib>
  using namespace metal;
  struct V { float4 position [[position]]; };
  vertex V registeredVertex(uint i [[vertex_id]]) {
    const float2 p[6]={float2(-1,1),float2(-1,-1),float2(1,-1),float2(-1,1),float2(1,-1),float2(1,1)};
    return {float4(p[i],0,1)};
  }
  fragment float4 registeredFragment(V in [[stage_in]],constant float* u [[buffer(0)]],
    texture2d<float> photo [[texture(0)]],texture2d<float> atlas [[texture(1)]],texture2d<float> panel [[texture(2)]]) {
    constexpr sampler sample(coord::normalized,address::clamp_to_edge,filter::linear);
    float2 viewport=float2(u[0],u[1]), source=float2(u[2],u[3]);
    float2 rectOrigin=float2(u[19],u[20]), rectExtent=float2(u[21],u[22]);
    float2 uv=(in.position.xy/viewport-rectOrigin)/rectExtent;
    float inside=step(0.0,uv.x)*step(uv.x,1.0)*step(0.0,uv.y)*step(uv.y,1.0);
    float2 halfTexel=0.5/source, sampleUV=clamp(uv,halfTexel,1.0-halfTexel);
    float sourceAlpha=mix(inside,1.0,u[23]);
    float3 rgb=photo.sample(sample,sampleUV).rgb, c=atlas.sample(sample,sampleUV).rgb*inside, accent=float3(u[7],u[8],u[9]);
    float2 outside=max(max(-uv,uv-1.0),0.0)*rectExtent*viewport;
    if (u[24]>0) rgb*=clamp(1.0-length(outside)/u[24],0.0,1.0);
    float hi=max(rgb.r,max(rgb.g,rgb.b)),lo=min(rgb.r,min(rgb.g,rgb.b));
    float3 color=mix(rgb,float3(lo)+(hi-lo)*accent,clamp(c.g+c.b,0.0,1.0));
    color*=1+(u[4]-1)*c.g+(u[25]-1)*c.b;
    float reach=1-smoothstep(u[6]-0.16,u[6]+0.05,1-c.b);
    color+=accent*c.b*reach*clamp(u[5],0.0,1.5)*0.38;
    float3 q=float3(dot(float3(u[10],u[11],u[12]),float3(uv,1)),dot(float3(u[13],u[14],u[15]),float3(uv,1)),dot(float3(u[16],u[17],u[18]),float3(uv,1)));
    float2 local=q.xy/q.z;
    float panelInside=step(0.0,local.x)*step(local.x,1.0)*step(0.0,local.y)*step(local.y,1.0);
    color=mix(color,panel.sample(sample,local).rgb,c.r*panelInside);
    return float4(clamp(color,0.0,1.0)*sourceAlpha,sourceAlpha);
  }
  """
}
