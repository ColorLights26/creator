import Foundation
import CoreGraphics
import CoreText
import ImageIO
import Metal
import simd
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

struct SceneCatalogSongPlayback: Equatable {
  let positionSeconds: Double
  let durationSeconds: Double
  let playing: Bool

  static func parse(_ raw: Any) -> Self? {
    guard let value = raw as? [String: Any],
      Set(value.keys) == ["positionMs", "durationMs", "playing"],
      let position = value["positionMs"] as? NSNumber,
      let duration = value["durationMs"] as? NSNumber,
      let playing = value["playing"] as? NSNumber,
      CFGetTypeID(position) != CFBooleanGetTypeID(),
      CFGetTypeID(duration) != CFBooleanGetTypeID(), CFGetTypeID(playing) == CFBooleanGetTypeID(),
      position.doubleValue.isFinite, duration.doubleValue.isFinite,
      position.doubleValue.rounded() == position.doubleValue,
      duration.doubleValue.rounded() == duration.doubleValue,
      duration.doubleValue > 0, duration.doubleValue < Double(Int64.max),
      position.doubleValue >= 0, position.doubleValue <= duration.doubleValue
    else { return nil }
    return Self(positionSeconds: position.doubleValue/1000,
      durationSeconds: duration.doubleValue/1000, playing: playing.boolValue)
  }
}

/// Session-owned identity, never part of a persistent scene recipe.
struct SceneCatalogSongContent: Equatable {
  let identity: String
  let title: String
  let artist: String
  let artwork: Data?
  let accent: UInt32
  var artworkOnly: Bool = false
  var artworkBrightness: Double = 1
  var artworkSaturation: Double = 1
  var artworkOpacity: Double = 1
  var providerName: String? = nil
  var providerMark: Data? = nil
  var playback: SceneCatalogSongPlayback? = nil

  static func parse(_ value: [String: Any]) -> Self? {
    guard Set(value.keys).isSubset(of: ["schemaVersion", "identity", "title", "artist", "artworkBytes", "accentArgb", "artworkOnly", "artworkBrightness", "artworkSaturation", "artworkOpacity", "providerName", "providerMarkBytes", "playback"]),
      let schema = value["schemaVersion"] as? NSNumber,
      CFGetTypeID(schema) != CFBooleanGetTypeID(), schema.doubleValue == 1,
      let identity = value["identity"] as? String, !identity.isEmpty, identity.utf16.count <= 512,
      let title = value["title"] as? String, title.utf16.count <= 512,
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
    if let raw = value["artworkOnly"] {
      guard let flag = raw as? NSNumber, CFGetTypeID(flag) == CFBooleanGetTypeID() else { return nil }
    }
    let artworkOnly = value["artworkOnly"] as? Bool ?? false
    let providerName = value["providerName"] as? String
    let providerMark = value["providerMarkBytes"] as? Data
    guard value["providerName"] == nil || (providerName != nil && providerName!.utf16.count <= 512),
      value["providerMarkBytes"] == nil || (providerMark != nil && (1...524_288).contains(providerMark!.count)) else { return nil }
    var playback: SceneCatalogSongPlayback?
    if let raw = value["playback"] {
      guard let parsed = SceneCatalogSongPlayback.parse(raw) else { return nil }
      playback = parsed
    }
    guard artworkOnly ? (title.isEmpty && value["artist"] == nil && artwork != nil &&
      providerName == nil && providerMark == nil && playback == nil) : !title.isEmpty else { return nil }
    func unit(_ key: String) -> Double? {
      guard let raw = value[key] else { return 1 }
      guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
        number.doubleValue.isFinite, (0...1).contains(number.doubleValue) else { return nil }
      return number.doubleValue
    }
    guard let brightness = unit("artworkBrightness"), let saturation = unit("artworkSaturation"),
      let opacity = unit("artworkOpacity") else { return nil }
    return Self(identity: identity, title: title, artist: artist, artwork: artwork,
      accent: accent.uint32Value, artworkOnly: artworkOnly, artworkBrightness: brightness,
      artworkSaturation: saturation, artworkOpacity: opacity,
      providerName: providerName, providerMark: providerMark, playback: playback)
  }

  func resolvedProviderMark(maximumPixelSize: Int = 128) -> CGImage? {
    guard let data = providerMark, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateThumbnailAtIndex(source, 0, [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
      kCGImageSourceShouldCacheImmediately: true,
    ] as CFDictionary)
  }

  /// One bounded source decode/treatment when session content changes. The
  /// scene does not choose a musical state or appearance; it receives both.
  func resolvedArtwork(maximumPixelSize: Int) -> CGImage? {
    guard let data = artwork, let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        kCGImageSourceShouldCacheImmediately: true,
      ] as CFDictionary) else { return nil }
    if artworkBrightness == 1 && artworkSaturation == 1 && artworkOpacity == 1 { return image }
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(data: nil, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
      let data = context.data else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let bytes = data.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
    let gain = artworkBrightness * artworkOpacity
    func byte(_ value: Double) -> UInt8 { UInt8(max(0, min(255, value.rounded()))) }
    for offset in stride(from: 0, to: image.width * image.height * 4, by: 4) {
      let r = Double(bytes[offset]), g = Double(bytes[offset + 1]), b = Double(bytes[offset + 2])
      let gray = (r * 0.2126 + g * 0.7152 + b * 0.0722) * (1 - artworkSaturation)
      bytes[offset] = byte((gray + r * artworkSaturation) * gain)
      bytes[offset + 1] = byte((gray + g * artworkSaturation) * gain)
      bytes[offset + 2] = byte((gray + b * artworkSaturation) * gain)
      bytes[offset + 3] = byte(Double(bytes[offset + 3]) * artworkOpacity)
    }
    return context.makeImage()
  }
}

/// Shared native panel primitives. Input images and service identity come from
/// the scene host; this helper never chooses a recording or a streaming brand.
enum SceneSongPanelDrawing {
  private static var symbols = [String: CGImage]()
  private static let symbolLock = NSLock()

  static func color(_ argb: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((argb >> 16) & 255)/255, green: CGFloat((argb >> 8) & 255)/255,
      blue: CGFloat(argb & 255)/255, alpha: alpha)
  }

  static func image(_ image: CGImage, in rect: CGRect, radius: CGFloat,
                    context: CGContext, fit: Bool = false) {
    guard rect.width > 0, rect.height > 0 else { return }
    let sx = rect.width/CGFloat(image.width), sy = rect.height/CGFloat(image.height)
    let scale = fit ? min(sx, sy) : max(sx, sy)
    let size = CGSize(width: CGFloat(image.width)*scale, height: CGFloat(image.height)*scale)
    context.saveGState()
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.clip()
    context.interpolationQuality = .high
    context.translateBy(x: rect.midX-size.width/2, y: rect.midY+size.height/2)
    context.scaleBy(x: 1, y: -1)
    context.draw(image, in: CGRect(origin: .zero, size: size))
    context.restoreGState()
  }

  @discardableResult
  static func text(_ value: String, rect: CGRect, size: CGFloat, color: UInt32,
                   context: CGContext, maxLines: Int = 1, lineHeight: CGFloat = 1.15,
                   alpha: CGFloat = 1, medium: Bool = false, right: Bool = false) -> CGFloat {
    let font = CTFontCreateWithName((medium ? "HelveticaNeue-Medium" : "HelveticaNeue") as CFString, size, nil)
    let attributes: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): font,
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): self.color(color, alpha: alpha),
    ]
    let attributed = NSAttributedString(string: value, attributes: attributes)
    let typesetter = CTTypesetterCreateWithAttributedString(attributed)
    let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
    var offset = 0, count = 0
    while offset < attributed.length && count < maxLines && rect.width > 0 {
      let length = max(1, CTTypesetterSuggestLineBreak(typesetter, offset, Double(rect.width)))
      let range = CFRange(location: offset, length: count == maxLines-1 ? attributed.length-offset : length)
      let line = CTTypesetterCreateLine(typesetter, range)
      let fitted = count == maxLines-1 ? CTLineCreateTruncatedLine(line, Double(rect.width), .end, ellipsis) ?? line : line
      let width = CGFloat(CTLineGetTypographicBounds(fitted, nil, nil, nil))
      context.saveGState(); context.clip(to: rect)
      context.translateBy(x: right ? rect.maxX-width : rect.minX,
        y: rect.minY+size+CGFloat(count)*size*lineHeight)
      context.scaleBy(x: 1, y: -1); context.textPosition = .zero
      CTLineDraw(fitted, context); context.restoreGState()
      offset += length; count += 1
    }
    return CGFloat(max(1, count))*size*lineHeight
  }

  static func icon(_ name: String, rect: CGRect, color: UInt32, context: CGContext,
                   alpha: CGFloat = 1) throws {
    symbolLock.lock(); defer { symbolLock.unlock() }
    let symbol: CGImage
    if let cached = symbols[name] { symbol = cached }
    else {
      let size = CGSize(width: 128, height: 128)
      #if canImport(UIKit)
      guard let source = UIImage(systemName: name,
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 100, weight: .regular)) else { throw DrawingError.symbol(name) }
      let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
      let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
        let scale = min(size.width/source.size.width, size.height/source.size.height)
        let target = CGRect(x: (size.width-source.size.width*scale)/2,
          y: (size.height-source.size.height*scale)/2,
          width: source.size.width*scale, height: source.size.height*scale)
        source.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: target)
      }
      guard let decoded = image.cgImage else { throw DrawingError.symbol(name) }
      symbol = decoded
      #else
      guard let source = NSImage(systemSymbolName: name, accessibilityDescription: nil),
        let configured = source.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 100, weight: .regular)) else { throw DrawingError.symbol(name) }
      var proposed = CGRect(origin: .zero, size: size)
      guard let decoded = configured.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
      else { throw DrawingError.symbol(name) }
      symbol = decoded
      #endif
      if symbols.count >= 48 { symbols.removeAll(keepingCapacity: true) }
      symbols[name] = symbol
    }
    context.saveGState()
    context.translateBy(x: rect.minX, y: rect.maxY); context.scaleBy(x: 1, y: -1)
    let bounds = CGRect(origin: .zero, size: rect.size)
    context.clip(to: bounds, mask: symbol)
    context.setFillColor(self.color(color, alpha: alpha)); context.fill(bounds)
    context.restoreGState()
  }

  static func clock(_ seconds: Double) -> String {
    let value = max(0, seconds.isFinite ? Int(min(seconds, Double(Int.max/1000))) : 0)
    return "\(value/60):\(String(format: "%02d", value%60))"
  }
  enum DrawingError: Error { case symbol(String) }
}

/// The existing scene supplies signals and host time. No clock or detector.
final class SceneCatalogSongStripState {
  private(set) var bars: [Float]
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

  init(barCount: Int = 45) { bars = [Float](repeating: 0, count: max(0, min(45, barCount))) }

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
        let position = Float(i) / Float(max(1, bars.count - 1)) * Float(spectrum.count - 1)
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

/// The floating card observes the same event envelope as the strip. Its slow
/// perimeter reflection uses owner time; musical accents use supplied signals.
final class SceneFloatingSongCardState {
  private let beats = SceneCatalogSongStripState(barCount: 0)
  private var frame: SceneRenderSignalFrameV2?
  private var previousHost: Double?
  private var playing = false
  private(set) var phase: Float = 0
  private(set) var pulse: Float = 0
  private(set) var levels = [Float](repeating: 0, count: 5)
  var needsFrames: Bool { playing }

  func consume(_ next: SceneRenderSignalFrameV2) -> Bool {
    if next.sessionId != frame?.sessionId || next.usesMappedMusicAuthority != frame?.usesMappedMusicAuthority {
      levels = [Float](repeating: 0, count: 5); pulse = 0
    }
    frame = next
    return beats.consume(next)
  }
  func setPlaying(_ next: Bool, hostTime: Double) {
    playing = next; previousHost = hostTime; beats.setPlaying(next, hostTime: hostTime)
    if !next { pulse = 0; levels = [Float](repeating: 0, count: 5); frame = nil }
  }
  func advance(hostTime: Double, reducedMotion: Bool) {
    let dt = hostTime.isFinite ? min(0.1, max(0, previousHost.map { hostTime-$0 } ?? 1/30)) : 0
    previousHost = hostTime.isFinite ? hostTime : nil
    beats.advance(hostTime: hostTime, reducedMotion: reducedMotion)
    guard playing, !reducedMotion else { pulse = 0; levels = [Float](repeating: 0, count: 5); return }
    phase = (phase+Float(dt/8)).truncatingRemainder(dividingBy: 1)
    let target = pow(beats.pulse, 1.8)
    pulse += (target-pulse)*Float(1-exp(-dt/(target > pulse ? 0.045:0.20)))
    if target == 0 && pulse < 0.0001 { pulse = 0 }
    let active = frame.map { $0.available && $0.fresh && $0.musicActive } == true
    let mapped = frame?.usesMappedMusicAuthority == true
    func unit(_ x: Float) -> Float { x.isFinite ? min(1,max(0,x)):0 }
    let spectrum = active ? frame!.spectrumSummary.map(unit) : [Float](repeating: 0,count: 7)
    let channels = active ? frame!.channels.map(unit) : [Float](repeating: 0,count: 4)
    let bands = [max(spectrum[0],spectrum[1]),spectrum[2],spectrum[3],spectrum[4],max(spectrum[5],spectrum[6])]
    let broad = [channels[0],(channels[0]+channels[1])/2,channels[1],(channels[1]+channels[2])/2,channels[2]]
    let accents: [Float] = [0.8,1,0.6,0.9,0.55]
    for i in levels.indices {
      let level: Float = !active ? 0 : mapped ? unit(unit(frame!.dynamics[2])*0.24+beats.pulse*0.76*accents[i]) :
        unit(sqrt(bands[i]*0.78+broad[i]*0.22)*0.78+beats.pulse*0.22*accents[i])
      levels[i] += (level-levels[i])*Float(1-exp(-dt/(level > levels[i] ? 0.045:0.18)))
      if level == 0 && levels[i] < 0.003 { levels[i] = 0 }
    }
  }
}

@available(iOS 15.0, *)
final class SceneFloatingSongCardRenderer {
  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let pipeline: MTLRenderPipelineState
  private var content: SceneCatalogSongContent?
  private var artwork: CGImage?
  private var identity: MTLTexture?
  private var rasterKey: String?
  private var revision = 0
  private(set) var identityRasterCount = 0

  init(device: MTLDevice) throws {
    self.device = device
    guard let queue = device.makeCommandQueue() else { throw Failure.graphics }
    self.queue = queue
    let library = try device.makeLibrary(source: Self.shader, options: nil)
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = library.makeFunction(name: "floatingCardVertex")
    descriptor.fragmentFunction = library.makeFunction(name: "floatingCardFragment")
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
  }

  @discardableResult
  func updateSongContent(_ next: SceneCatalogSongContent?) -> Bool {
    var previous = content, visual = next
    previous?.playback = nil; visual?.playback = nil
    previous?.providerName = nil; visual?.providerName = nil
    previous?.providerMark = nil; visual?.providerMark = nil
    guard previous != visual else { content = next; return false }
    if next?.artwork != content?.artwork || next?.artworkBrightness != content?.artworkBrightness ||
      next?.artworkSaturation != content?.artworkSaturation || next?.artworkOpacity != content?.artworkOpacity {
      artwork = next?.resolvedArtwork(maximumPixelSize: 512)
    }
    content = next; revision += 1; rasterKey = nil
    return true
  }

  func render(state: SceneFloatingSongCardState, logicalSize: CGSize, hostTime: Double,
      reducedMotion: Bool, width: Int, height: Int,
      outputAllocator: SceneSurfaceNativeOutputAllocator) throws -> MTLTexture {
    guard width > 0, height > 0, width <= 8192, height <= 8192,
      logicalSize.width > 0, logicalSize.height > 0 else { throw Failure.graphics }
    state.advance(hostTime: hostTime, reducedMotion: reducedMotion)
    let scale = min(1.2, min(logicalSize.width/402, logicalSize.height/500))
    let body = CGRect(x:(logicalSize.width-min(logicalSize.width*0.84,420))/2,
      y:(logicalSize.height-157.6*scale)/2,width:min(logicalSize.width*0.84,420),height:157.6*scale)
    try prepareIdentity(logicalSize: logicalSize, body: body, scale: scale, width: width, height: height)
    let uniforms: [Float] = [Float(logicalSize.width),Float(logicalSize.height),Float(scale),
      Float(body.minX),Float(body.minY),Float(body.width),Float(body.height),state.phase,state.pulse]+state.levels
    guard let output = try SceneSurfaceNativeOutputAllocator.makeTexture(device:device,width:width,height:height,allocator:outputAllocator),
      let command = queue.makeCommandBuffer(), let identity else { throw Failure.graphics }
    let pass=MTLRenderPassDescriptor(); pass.colorAttachments[0].texture=output
    pass.colorAttachments[0].loadAction = .dontCare; pass.colorAttachments[0].storeAction = .store
    guard let encoder=command.makeRenderCommandEncoder(descriptor:pass) else { throw Failure.graphics }
    encoder.setRenderPipelineState(pipeline)
    uniforms.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!,length:$0.count,index:0) }
    encoder.setFragmentTexture(identity,index:0); encoder.drawPrimitives(type:.triangleStrip,vertexStart:0,vertexCount:4); encoder.endEncoding()
    command.commit(); command.waitUntilCompleted()
    guard command.status == .completed else { throw command.error ?? Failure.graphics }
    return output
  }

  private func prepareIdentity(logicalSize: CGSize, body: CGRect, scale s: CGFloat, width: Int, height: Int) throws {
    let ratio=min(1,2048/CGFloat(max(width,height)))
    let w=max(1,Int(CGFloat(width)*ratio)),h=max(1,Int(CGFloat(height)*ratio))
    let key="\(w):\(h):\(logicalSize):\(revision)"
    if key == rasterKey, identity != nil { return }
    let rasterStarted = CACurrentMediaTime()
    defer { sceneDiagnosticLog(String(format: "[SceneRasterCost] song_strip identity %dx%d logical=%.0fx%.0f ms=%.1f main=%@", w, h, logicalSize.width, logicalSize.height, (CACurrentMediaTime() - rasterStarted) * 1000, Thread.isMainThread ? "true" : "false")) }
    guard let c=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,
      space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue),let pixels=c.data else { throw Failure.graphics }
    c.translateBy(x:0,y:CGFloat(h)); c.scaleBy(x:CGFloat(w)/logicalSize.width,y:-CGFloat(h)/logicalSize.height)
    let draw=SceneSongPanelDrawing.self
    c.saveGState(); c.addPath(CGPath(roundedRect:body,cornerWidth:25*s,cornerHeight:25*s,transform:nil)); c.clip()
    guard let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[draw.color(0xff1b1b20),draw.color(0xff0c0c0f)] as CFArray,locations:[0,1]) else { throw Failure.graphics }
    c.drawLinearGradient(gradient,start:body.origin,end:CGPoint(x:body.maxX,y:body.maxY),options:[]); c.restoreGState()
    let x=body.minX+19.2*s,y=body.minY+19.2*s
    let cover=CGRect(x:x,y:y,width:49*s,height:49*s)
    if let artwork { draw.image(artwork,in:cover,radius:8*s,context:c) }
    else {
      c.setFillColor(draw.color(0xff292e38)); c.fill(cover)
      try draw.icon("music.note",rect:cover.insetBy(dx:12*s,dy:12*s),color:0xffaeb6c6,context:c)
    }
    let title=content?.title ?? "", artist=content?.artist ?? ""
    let textWidth=max(1,body.width-129.4*s)
    draw.text(title.isEmpty ? "Your music":title,rect:CGRect(x:x+60*s,y:y+4.15*s,width:textWidth,height:19.5*s),size:15*s,color:0xfff5f5f7,context:c,lineHeight:1.3,medium:true)
    draw.text(title.isEmpty ? "Waiting for a song":artist.isEmpty ? "Now playing":artist,
      rect:CGRect(x:x+60*s,y:y+26.65*s,width:textWidth,height:18.2*s),size:13*s,color:0xffb7b7c0,context:c,lineHeight:1.4)
    let ty=y+63*s
    draw.text("—:—",rect:CGRect(x:x,y:ty,width:32*s,height:13.2*s),size:11*s,color:0xffb7b7c0,context:c,lineHeight:1.2)
    draw.text("—:—",rect:CGRect(x:body.maxX-51.2*s,y:ty,width:32*s,height:13.2*s),size:11*s,color:0xffb7b7c0,context:c,lineHeight:1.2,right:true)
    let bar=CGRect(x:x+41*s,y:ty+5.1*s,width:body.width-120.4*s,height:3*s)
    c.setFillColor(draw.color(0xff414147)); c.fill(bar)
    c.setFillColor(draw.color(0xffe6e6eb)); c.fill(CGRect(x:bar.minX,y:bar.minY,width:bar.width*0.24,height:bar.height))
    let cy=ty+29.2*s
    for (offset,name,size): (CGFloat,String,CGFloat) in [(-62,"backward.end.fill",23),(0,"pause.fill",29),(62,"forward.end.fill",23)] {
      try draw.icon(name,rect:CGRect(x:body.midX+(offset-size/2)*s,y:cy+(29-size)*s/2,width:size*s,height:size*s),color:0xfff5f5f7,context:c)
    }
    try draw.icon("airplay.audio",rect:CGRect(x:body.maxX-37.2*s,y:cy+5.5*s,width:18*s,height:18*s),color:0xffb7b7c0,context:c)
    let descriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:w,height:h,mipmapped:false)
    descriptor.usage = .shaderRead; descriptor.storageMode = .shared
    guard let texture=device.makeTexture(descriptor:descriptor) else { throw Failure.graphics }
    texture.replace(region:MTLRegionMake2D(0,0,w,h),mipmapLevel:0,withBytes:pixels,bytesPerRow:w*4)
    identity=texture; rasterKey=key; identityRasterCount += 1
  }

  private enum Failure: Error { case graphics }
  private static let shader = """
  #include <metal_stdlib>
  using namespace metal;
  struct CardVertex { float4 position [[position]]; float2 uv; };
  vertex CardVertex floatingCardVertex(uint id [[vertex_id]]) {
    const float2 p[4]={float2(-1,-1),float2(1,-1),float2(-1,1),float2(1,1)};
    return {float4(p[id],0,1),float2((p[id].x+1)*.5,(1-p[id].y)*.5)};
  }
  float cardRect(float2 p,float2 halfSize,float r) {
    float2 q=abs(p)-halfSize+r; return length(max(q,0.0))+min(max(q.x,q.y),0.0)-r;
  }
  fragment float4 floatingCardFragment(CardVertex v [[stage_in]],constant float *u [[buffer(0)]],texture2d<float> identity [[texture(0)]]) {
    constexpr sampler smp(filter::linear,address::clamp_to_edge);
    float2 point=v.uv*float2(u[0],u[1]); float s=u[2];
    float2 center=float2(u[3]+u[5]*.5,u[4]+u[6]*.5),halfSize=float2(u[5],u[6])*.5;
    float2 p=point-center; float d=cardRect(p,halfSize-1.5*s,23.5*s),aa=max(fwidth(d),.35*s);
    float pulse=u[8],phase=u[7],angle=fract(atan2(p.y,p.x)/6.2831853-phase+1.0);
    float stops[7]={0,.50-.18*pulse,.62-.15*pulse,.76-.10*pulse,.86,.93,1};
    float brightness=.60+.28*pulse;
    float4 colors[7]={float4(.498,.902,.949,0),float4(.498,.902,.949,0),float4(.498,.902,.949,brightness*.18),float4(.557,.918,.957,brightness*.60),float4(.863,.984,1,brightness),float4(.557,.918,.957,brightness*.30),float4(.498,.902,.949,0)};
    float4 neon=colors[6];
    for (int i=0;i<6;i++) { if (angle>=stops[i]&&angle<=stops[i+1]) { neon=mix(colors[i],colors[i+1],clamp((angle-stops[i])/max(.001,stops[i+1]-stops[i]),0.0,1.0)); break; } }
    float core=1-smoothstep((.85+.3*pulse)*s-aa,(.85+.3*pulse)*s+aa,abs(d));
    float outside=step(-4.5*s,d);
    float soft=exp(-.5*pow(d/((2.8+2*pulse)*s),2.0))*.55*outside;
    float broad=exp(-.5*pow(d/((5+3*pulse)*s),2.0))*.25*pulse*outside;
    float alpha=clamp(neon.a*(core+soft+broad),0.0,1.0);
    float base=(1-smoothstep(.5*s-aa,.5*s+aa,abs(d)))*.20;
    float4 out=identity.sample(smp,v.uv);
    out=float4(float3(.686,.729,.776)*base,base)+out*(1-base);
    out=float4(neon.rgb*alpha,alpha)+out*(1-alpha);
    const float rests[5]={.20,.35,.50,.35,.20};
    float2 waveOrigin=float2(u[3]+u[5]-41.2*s,u[4]+33.7*s);
    for (int i=0;i<5;i++) {
      float level=u[9+i],h=(rests[i]+(1-rests[i])*level)*20*s;
      float2 q=point-(waveOrigin+float2((i+.5)*4.4*s,10*s));
      float sd=cardRect(q,float2(1*s,h*.5),1*s);
      float cover=1-smoothstep(-aa,aa,sd);
      float3 color=mix(float3(.580,.580,.624),float3(.639,.902,.929),level);
      out=float4(color*cover,cover)+out*(1-cover);
    }
    return out;
  }
  """
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
    let rasterStarted = CACurrentMediaTime()
    defer { sceneDiagnosticLog(String(format: "[SceneRasterCost] song_panel identity %dx%d logical=%.0fx%.0f ms=%.1f main=%@", w, h, logicalSize.width, logicalSize.height, (CACurrentMediaTime() - rasterStarted) * 1000, Thread.isMainThread ? "true" : "false")) }
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
    if let image = content?.resolvedArtwork(maximumPixelSize: 256) {
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
