#if canImport(scene_program_native)
import Foundation
import CoreGraphics
import CoreImage
import Metal
import MetalKit
import ImageIO
import CryptoKit
import scene_program_native

/// Native owner of one authored instance. It runs on the existing scene queue,
/// including PiP; no Dart callback, independent ticker or audio source.
@available(iOS 15.0, *)
final class SceneCreatorNativeScene {
  let definition: SceneCreatorCatalog.Program
  private let instance: OpaquePointer
  private let renderer: SceneCreatorCommandRenderer
  private var options: [Float]
  private var reactive: Bool
  private var playing = false
  private var hostTime = 0.0
  private var signalError: Error?
  private var updates = 0, updateTotal = 0.0, updateMaximum = 0.0
  var metrics: [String: Any] { ["programId": "creator_" + definition.id,
    "instance": String(describing: instance), "updates": updates,
    "simulationAverageMicros": updateTotal / Double(max(1, updates)), "simulationMaximumMicros": updateMaximum] }

  static func controls(program: SceneCreatorCatalog.Program, options: [String: Any], mode: String?, reactive: Bool) -> [Float]? {
    guard program.isNative, program.allows(reactive: reactive), mode == nil || mode == "default",
      Set(options.keys).isSubset(of: Set(SceneCreatorCatalog.controlRanges.keys).union(["Music Reactive"])) else { return nil }
    var values = program.controls
    for (key, raw) in options {
      if key == "Music Reactive" {
        guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID(), number.boolValue == reactive else { return nil }
      } else {
        guard let value = SceneCreatorCatalog.number(raw), SceneCreatorCatalog.controlRanges[key]?.contains(Float(value)) == true else { return nil }
        values[key] = Float(value)
      }
    }
    return ["intensity", "speed", "detail", "glow"].map { values[$0]! } + program.colors
  }

  init(program: SceneCreatorCatalog.Program, options: [String: Any], mode: String?, reactive: Bool,
       seed: UInt32?, device: MTLDevice) throws {
    guard let controls = Self.controls(program: program, options: options, mode: mode, reactive: reactive),
      let hash = program.nativeBuild["hash"] as? String else { throw SceneCreatorFailure("Invalid native scene configuration") }
    self.definition = program; self.options = controls; self.reactive = reactive
    guard let handle = ("creator_" + program.id).withCString({ name in hash.withCString { cp_create(name, $0, seed ?? program.seed) } })
    else { throw SceneCreatorFailure(String(cString: cp_error(nil))) }
    instance = handle
    do { renderer = try SceneCreatorCommandRenderer(device: device, program: program) }
    catch { cp_destroy(handle); throw error }
  }
  deinit { cp_destroy(instance) }

  func changeControls(_ options: [Float], reactive: Bool) {
    self.options = options; self.reactive = reactive
    if configure() != 1 { signalError = failure() }
  }
  var currentControls: [Float] { options }
  var currentReactive: Bool { reactive }

  func consume(_ frame: SceneRenderSignalFrameV2) -> Bool {
    let bytes = Self.encode(frame)
    let ok = bytes.withUnsafeBufferPointer { cp_consume(instance, $0.baseAddress, UInt32($0.count)) }
    if ok != 1 { signalError = failure() }
    return ok == 1
  }
  func setPlaying(_ value: Bool, hostTime: Double) {
    playing = value; self.hostTime = hostTime
    if configure() != 1 { signalError = failure() }
  }
  private func configure() -> Int32 {
    options.withUnsafeBufferPointer { cp_configure(instance, $0.baseAddress, UInt32($0.count), reactive ? 1 : 0, playing ? 1 : 0, hostTime) }
  }
  private func failure() -> Error { SceneCreatorFailure(String(cString: cp_error(instance))) }

  func render(size: CGSize, hostTime: Double, reducedMotion: Bool, width: Int, height: Int,
              outputAllocator: SceneSurfaceNativeOutputAllocator) throws -> MTLTexture {
    if let signalError { throw signalError }
    self.hostTime = hostTime
    guard configure() == 1, cp_update(instance, size.width, size.height, hostTime, reducedMotion ? 1 : 0) == 1,
      cp_draw(instance) == 1 else { throw failure() }
    let micros = cp_update_micros(instance)
    updates += 1; updateTotal += micros; updateMaximum = max(updateMaximum, micros)
    let count = Int(cp_command_length(instance))
    guard count <= 262144 else { throw SceneCreatorFailure("Native command budget exceeded") }
    let commands = UnsafeBufferPointer(start: cp_commands(instance), count: count)
    return try renderer.render(commands: commands, size: size, width: width, height: height, outputAllocator: outputAllocator)
  }

  private static func encode(_ f: SceneRenderSignalFrameV2) -> [UInt8] {
    var bytes = [UInt8](); bytes.reserveCapacity(520)
    func integer<T: FixedWidthInteger>(_ value: T) { var v = value.littleEndian; withUnsafeBytes(of: &v) { bytes.append(contentsOf: $0) } }
    integer(UInt32(0x32565253)); integer(UInt16(2))
    let flags: UInt16 = (f.available ? 1 : 0) | (f.fresh ? 2 : 0) | (f.musicActive ? 4 : 0) | (f.tonalAvailable ? 8 : 0)
    integer(flags); integer(UInt32(520)); integer(UInt32(0)); integer(f.sessionId); integer(f.sequence); integer(f.audioTimestampMicros)
    for values in [f.dynamics, f.channels, f.spectrumSummary, f.instantSpectrum, f.smoothedSpectrum, f.semantics, f.rhythm, f.onsets, f.tonal] {
      for v in values { integer(v.bitPattern) }
    }
    for event in [f.impact, f.accent, f.beat, f.flash] {
      integer(event.serial); integer(event.timestampMicros); integer(event.strength.bitPattern)
      integer(event.band.rawValue); integer(UInt8(event.active ? 1 : 0)); integer(UInt16(0))
    }
    return bytes
  }
}

struct SceneCreatorFailure: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}

/// CPU only reads validated geometry. Vector raster, materials, clip masks and
/// group composition stay on the GPU, then feed the existing output allocator.
@available(iOS 15.0, *)
final class SceneCreatorCommandRenderer {
  private let device: MTLDevice
  private let vector: SceneCatalogVectorRenderer
  private let materials: SceneCreatorMaterialRenderer
  private let particles: SceneCreatorPointRenderer
  private let context: CIContext
  private let queue: MTLCommandQueue
  private let program: SceneCreatorCatalog.Program
  private let images: [MTLTexture]
  private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

  init(device: MTLDevice, program: SceneCreatorCatalog.Program) throws {
    self.device = device; self.program = program
    vector = try SceneCatalogVectorRenderer(device: device)
    materials = try SceneCreatorMaterialRenderer(device: device, definitions: program.nativeBuild["materials"] as? [String: [String: Any]] ?? [:])
    particles = try SceneCreatorPointRenderer(device: device)
    guard let queue = device.makeCommandQueue() else { throw SceneCreatorFailure("Composition queue unavailable") }
    self.queue = queue
    context = CIContext(mtlCommandQueue: queue, options: [.workingColorSpace: NSNull(), .cacheIntermediates: false])
    let loader = MTKTextureLoader(device: device)
    var textures = [MTLTexture](); var total = 0
    for key in program.images.keys.sorted() {
      guard let root = SceneCreatorCatalog.assetRoot, let path = program.images[key],
        let expected = (program.nativeBuild["imageHashes"] as? [String: String])?[key] else { throw SceneCreatorFailure("Missing bundled image identity") }
      let url = root.appendingPathComponent(path)
      let data = try Data(contentsOf: url)
      guard data.count <= 16 * 1024 * 1024,
        SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expected else { throw SceneCreatorFailure("Bundled image changed: \(path)") }
      guard let source = CGImageSourceCreateWithData(data as CFData, nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let width = properties[kCGImagePropertyPixelWidth] as? Int,
        let height = properties[kCGImagePropertyPixelHeight] as? Int,
        width > 0, height > 0, width <= 4096, height <= 4096 else { throw SceneCreatorFailure("Invalid image dimensions") }
      total += width * height * 4
      guard total <= 64 * 1024 * 1024 else { throw SceneCreatorFailure("Image texture budget exceeded") }
      let texture = try loader.newTexture(data: data, options: [.SRGB: false, .origin: MTKTextureLoader.Origin.topLeft])
      // MTKTextureLoader supplies straight alpha. Prepare premultiplied pixels
      // once so both image draws and material samplers match Flutter Canvas.
      let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
      descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]; descriptor.storageMode = .private
      guard let image = CIImage(mtlTexture: texture, options: [.colorSpace: colorSpace]),
        let prepared = device.makeTexture(descriptor: descriptor), let command = queue.makeCommandBuffer() else { throw SceneCreatorFailure("Image preparation unavailable") }
      context.render(image.premultiplyingAlpha(), to: prepared, commandBuffer: command,
        bounds: CGRect(x: 0, y: 0, width: width, height: height), colorSpace: colorSpace)
      command.commit(); command.waitUntilCompleted()
      guard command.status == .completed else { throw command.error ?? SceneCreatorFailure("Image preparation failed") }
      textures.append(prepared)
    }
    images = textures
  }

  private struct State {
    var transform = CGAffineTransform.identity
    var clips: [(SceneCatalogVectorPath, CGAffineTransform)] = []
  }
  private struct Saved {
    let state: State
    let parent: CIImage?
    let opacity: Float
    let blend: Int
  }

  func render(commands: UnsafeBufferPointer<Float>, size: CGSize, width: Int, height: Int,
              outputAllocator: SceneSurfaceNativeOutputAllocator) throws -> MTLTexture {
    let bounds = CGRect(x: 0, y: 0, width: width, height: height)
    let scale = CGAffineTransform(scaleX: CGFloat(width) / size.width, y: CGFloat(height) / size.height)
    let transparent = CIImage(color: CIColor.clear).cropped(to: bounds)
    var output = transparent
    if program.role == "background" {
      output = CIImage(color: CIColor(red: CGFloat(program.colors[0]), green: CGFloat(program.colors[1]), blue: CGFloat(program.colors[2]))).cropped(to: bounds)
    }
    var state = State(); var stack = [Saved]()
    var canvas = SceneCatalogVectorCanvas(); var batchBlend = 0
    var passes = 0; var retainedBytes = 0
    // CI retains the intermediate images until the final render. Account for
    // every allocation, including masks/groups, rather than only vector scratch.
    func account(_ w: Int, _ h: Int) throws {
      passes += 1; retainedBytes += w * h * 4
      guard passes <= 192, retainedBytes <= 128 * 1024 * 1024 else { throw SceneCreatorFailure("Scene intermediate texture/pass budget exceeded") }
    }
    func image(_ texture: MTLTexture) throws -> CIImage {
      guard let result = CIImage(mtlTexture: texture, options: [.colorSpace: colorSpace]) else { throw SceneCreatorFailure("Invalid GPU image") }
      return result
    }
    func composite(_ source: CIImage, _ destination: CIImage, _ blend: Int) -> CIImage {
      source.applyingFilter(blend == 1 ? "CIAdditionCompositing" : blend == 2 ? "CIScreenBlendMode" : "CISourceOverCompositing",
        parameters: [kCIInputBackgroundImageKey: destination]).cropped(to: bounds)
    }
    func clipped(_ source: CIImage) throws -> CIImage {
      var result = source
      for (path, transform) in state.clips {
        try account(width, height)
        let maskCanvas = SceneCatalogVectorCanvas(); maskCanvas.concat(transform)
        let paint = SceneCatalogVectorPaint(); paint.color = .init(0xffffffff)
        maskCanvas.drawPath(path, paint)
        let texture = try vector.render(canvas: maskCanvas, logicalWidth: size.width, logicalHeight: size.height,
          width: width, height: height, outputAllocator: nil)
        result = result.applyingFilter("CIBlendWithAlphaMask", parameters: [kCIInputBackgroundImageKey: transparent, kCIInputMaskImageKey: try image(texture)])
      }
      return result
    }
    func flush() throws {
      guard !canvas.draws.isEmpty else { return }
      try account(width, height)
      let texture = try vector.render(canvas: canvas, logicalWidth: size.width, logicalHeight: size.height,
        width: width, height: height, outputAllocator: nil)
      output = composite(try clipped(image(texture)), output, batchBlend)
      canvas = SceneCatalogVectorCanvas()
    }
    func append(_ path: SceneCatalogVectorPath, _ paint: SceneCatalogVectorPaint) throws {
      let blend = paint.blendMode == .plus ? 1 : paint.blendMode == .screen ? 2 : 0
      if blend != batchBlend { try flush(); batchBlend = blend }
      canvas.save(); canvas.concat(state.transform); canvas.drawPath(path, paint); canvas.restore()
    }
    let r = SceneCreatorCommandReader(commands)
    while !r.done {
      let op = try r.integer(1, 9), count = try r.integer(0, 262144), end = r.position + count
      guard end <= commands.count else { throw SceneCreatorFailure("Truncated native draw") }
      switch op {
      case 1:
        try flush(); stack.append(Saved(state: state, parent: nil, opacity: 1, blend: 0))
      case 2:
        try flush()
        guard let saved = stack.popLast() else { throw SceneCreatorFailure("Drawing stack underflow") }
        if let parent = saved.parent {
          output = output.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(saved.opacity))])
          output = composite(output, parent, saved.blend)
        }
        state = saved.state
      case 3:
        try flush(); let opacity = try r.value(), blend = try r.integer(0, 2)
        stack.append(Saved(state: state, parent: output, opacity: opacity, blend: blend)); output = transparent
      case 4:
        try flush()
        let matrix = CGAffineTransform(a: CGFloat(try r.value()), b: CGFloat(try r.value()), c: CGFloat(try r.value()), d: CGFloat(try r.value()), tx: CGFloat(try r.value()), ty: CGFloat(try r.value()))
        state.transform = matrix.concatenating(state.transform)
      case 5:
        try flush(); state.clips.append((try r.path(), state.transform))
      case 6:
        let paint = try r.paint(); try append(r.path(), paint)
      case 7:
        try flush(); let paint = try r.paint(), radius = try r.value(), count = try r.integer(0, 32768)
        var points = [SIMD2<Float>](); points.reserveCapacity(count)
        for _ in 0..<count { points.append(SIMD2(try r.value(), try r.value())) }
        if !points.isEmpty, radius > 0 {
          try account(width, height)
          let texture = try particles.render(points: points, radius: radius, paint: paint, transform: state.transform,
            size: size, width: width, height: height)
          output = composite(try clipped(image(texture)), output, paint.blendMode == .plus ? 1 : paint.blendMode == .screen ? 2 : 0)
        }
      case 8, 9:
        try flush()
        let index = try r.integer(0, op == 8 ? images.count - 1 : materials.count - 1), rect = try r.rect()
        let texture: MTLTexture; var opacity: Float = 1; let blend: Int
        if op == 8 { texture = images[index]; opacity = try r.value(); blend = try r.integer(0, 2) }
        else {
          blend = try r.integer(0, 2); let count = try r.integer(0, 1024)
          var values = [Float(rect.width), Float(rect.height)]
          for _ in 0..<count { values.append(try r.value()) }
          let samplerCount = try r.integer(0, 16); var sampled = [MTLTexture]()
          for _ in 0..<samplerCount { sampled.append(images[try r.integer(0, images.count - 1)]) }
          let physical = rect.applying(state.transform).applying(scale)
          let w = max(1, min(width, Int(ceil(abs(physical.width))))), h = max(1, min(height, Int(ceil(abs(physical.height)))))
          try account(w, h)
          texture = try materials.render(index: index, uniforms: values, images: sampled, width: w, height: h)
        }
        let placement = CGAffineTransform(scaleX: rect.width / CGFloat(texture.width), y: rect.height / CGFloat(texture.height))
          .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)).concatenating(state.transform).concatenating(scale)
        var content = try image(texture).transformed(by: placement)
        if opacity != 1 { content = content.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity))]) }
        output = composite(try clipped(content), output, blend)
      default: throw SceneCreatorFailure("Unknown drawing command")
      }
      guard r.position == end, stack.count <= 64 else { throw SceneCreatorFailure("Invalid native command layout") }
    }
    try flush()
    guard stack.isEmpty, let target = try SceneSurfaceNativeOutputAllocator.makeTexture(device: device, width: width, height: height, allocator: outputAllocator) else { throw SceneCreatorFailure("Native scene target unavailable") }
    guard let command = queue.makeCommandBuffer() else { throw SceneCreatorFailure("Composition command unavailable") }
    context.render(output, to: target, commandBuffer: command, bounds: bounds, colorSpace: colorSpace)
    command.commit(); command.waitUntilCompleted()
    guard command.status == .completed else { throw command.error ?? SceneCreatorFailure("Composition failed") }
    return target
  }
}

private final class SceneCreatorCommandReader {
  let data: UnsafeBufferPointer<Float>; var position = 0
  init(_ data: UnsafeBufferPointer<Float>) { self.data = data }
  var done: Bool { position == data.count }
  func value() throws -> Float {
    guard position < data.count, data[position].isFinite else { throw SceneCreatorFailure("Invalid native command field") }
    defer { position += 1 }; return data[position]
  }
  func integer(_ lo: Int, _ hi: Int) throws -> Int {
    let v = try value(); guard v.rounded() == v, v >= Float(lo), v <= Float(hi) else { throw SceneCreatorFailure("Invalid native command index") }; return Int(v)
  }
  func color() throws -> SceneCatalogVectorColor { .init(rgba: SIMD4(try value(), try value(), try value(), try value())) }
  func rect() throws -> CGRect { CGRect(x: CGFloat(try value()), y: CGFloat(try value()), width: CGFloat(try value()), height: CGFloat(try value())) }
  func path() throws -> SceneCatalogVectorPath {
    let p = SceneCatalogVectorPath(); p.evenOdd = try integer(0, 1) == 1
    let length = try integer(0, 262144), end = position + length
    guard end <= data.count else { throw SceneCreatorFailure("Truncated path") }
    while position < end {
      switch try integer(0, 4) {
      case 0: p.moveTo(Double(try value()), Double(try value()))
      case 1: p.lineTo(Double(try value()), Double(try value()))
      case 2: p.quadraticBezierTo(Double(try value()), Double(try value()), Double(try value()), Double(try value()))
      case 3: p.cubicTo(Double(try value()), Double(try value()), Double(try value()), Double(try value()), Double(try value()), Double(try value()))
      default: p.close()
      }
    }
    guard position == end else { throw SceneCreatorFailure("Invalid path length") }; return p
  }
  func paint() throws -> SceneCatalogVectorPaint {
    let p = SceneCatalogVectorPaint(); p.color = try color()
    p.blendMode = [.srcOver, .plus, .screen][try integer(0, 2)]
    p.strokeWidth = Double(try value()); p.style = p.strokeWidth == 0 ? .fill : .stroke
    p.strokeCap = [.butt, .round, .square][try integer(0, 2)]; p.strokeJoin = [.miter, .round, .bevel][try integer(0, 2)]
    let kind = try integer(0, 2); let a = SIMD2(try value(), try value()), b = SIMD2(try value(), try value())
    let count = try integer(0, 8); var colors = [SceneCatalogVectorColor](), stops = [Double]()
    for _ in 0..<count { colors.append(try color()); stops.append(Double(try value())) }
    if kind > 0 { p.shader = .init(radial: kind == 2, start: a, end: b, radius: kind == 2 ? b.x : 0, colors: colors, stops: stops) }
    return p
  }
}
#endif
