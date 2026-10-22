import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

/// Compiled by check_waveform_renderer.py next to the extracted production renderer
/// (`WaveformRendererCandidate`, optionally `WaveformRendererBaseline`). Renders the
/// golden signals exported by audiovisuals/test/music_waveform_test.dart on the Mac GPU,
/// compares them with the Flutter painter output, and times both renderers.
protocol WaveformRendering: AnyObject {
  func render(
    width: Int, height: Int, layer: SceneRenderV2WaveformLayer,
    state: SceneRenderV2WaveformState, quality: String, pointScale: Float,
    outputAllocator: SceneSurfaceNativeOutputAllocator?
  ) throws -> MTLTexture
}

struct WaveformHarnessFailure: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}

struct GoldenCase: Decodable {
  let name: String
  let signal: String
  let viewport: String
  let logicalWidth: Double
  let logicalHeight: Double
  let pixelWidth: Int
  let pixelHeight: Int
  let pointScale: Double
  let samples: [Double]
  let lineEnergy: Double
  let peakAmplitude: Double
  let impactLight: Double
  let lineVisibility: Double
  let opacity: Double
  let maximumDisplacementHeightFraction: Double
  let maximumDisplacementWidthFraction: Double
  let style: [String: UInt32]
}

/// Per-image comparison. Alpha is the coverage every pass adds to, so profiles and masks
/// are taken on alpha; colour is checked as mean premultiplied RGB error on the union.
struct ParityMetrics {
  var iouAlpha8 = 0.0
  var iouAlpha64 = 0.0
  var columnMeanMaxDiff = 0.0
  var columnMeanRelativeL1 = 0.0
  var rowMeanMaxDiff = 0.0
  var rowMeanRelativeL1 = 0.0
  var unionMeanAlphaDiff = 0.0
  var unionMaxAlphaDiff = 0
  var unionOver32Fraction = 0.0
  var unionMeanRGBDiff = 0.0
  var coreCentroidMeanOffset = 0.0
  var coreCentroidMaxOffset = 0.0
  var coreColumnsCompared = 0
  var alphaMassRatio = 0.0
  /// Share of the test footprint (alpha > 8) that lies inside the reference footprint.
  var containedInReference8 = 0.0

  var summary: String {
    String(
      format: "IoU(a>8)=%.3f IoU(a>64)=%.3f contained=%.3f | col-mean max=%.1f relL1=%.3f | row-mean max=%.1f relL1=%.3f | union mean|da|=%.2f max=%d >32:%.3f%% rgb=%.2f | core centroid mean=%.2fpx max=%.2fpx (%d flat cols) | mass=%.3f",
      iouAlpha8, iouAlpha64, containedInReference8, columnMeanMaxDiff, columnMeanRelativeL1,
      rowMeanMaxDiff, rowMeanRelativeL1,
      unionMeanAlphaDiff, unionMaxAlphaDiff, unionOver32Fraction * 100, unionMeanRGBDiff,
      coreCentroidMeanOffset, coreCentroidMaxOffset, coreColumnsCompared, alphaMassRatio)
  }

  var json: [String: Any] {
    [
      "iouAlpha8": iouAlpha8, "iouAlpha64": iouAlpha64, "containedInReference8": containedInReference8,
      "columnMeanMaxDiff": columnMeanMaxDiff, "columnMeanRelativeL1": columnMeanRelativeL1,
      "rowMeanMaxDiff": rowMeanMaxDiff, "rowMeanRelativeL1": rowMeanRelativeL1,
      "unionMeanAlphaDiff": unionMeanAlphaDiff, "unionMaxAlphaDiff": unionMaxAlphaDiff,
      "unionOver32Fraction": unionOver32Fraction, "unionMeanRGBDiff": unionMeanRGBDiff,
      "coreCentroidMeanOffset": coreCentroidMeanOffset,
      "coreCentroidMaxOffset": coreCentroidMaxOffset,
      "coreColumnsCompared": coreColumnsCompared, "alphaMassRatio": alphaMassRatio,
    ]
  }
}

/// Acceptance for the Flutter contract (quality `best`, identical logical input).
/// Each bound names the model difference that remains once geometry, blur sigma and
/// bloom profile agree: Skia's triple-box blur vs an analytic Gaussian, stroke
/// anti-aliasing (1 px), `plus` saturation order and 8-bit quantisation.
enum ParityTolerance {
  /// Glow footprint (alpha > 8, ~3%): where the haze visibly exists.
  static let iouAlpha8 = 0.90
  /// Visible body (alpha > 64, 25%): the stroke + near glow a user actually sees.
  static let iouAlpha64 = 0.85
  /// Mean alpha per column/row may drift by this many 8-bit steps (max over profile).
  static let profileMaxDiff = 12.0
  /// Total column/row profile energy within 15 % of Flutter.
  static let profileRelativeL1 = 0.15
  /// Per-pixel alpha over the union: mean under 8 steps, under 2 % of pixels off by >32.
  static let unionMeanAlphaDiff = 8.0
  static let unionOver32Fraction = 0.02
  /// The stroke centre must sit on the same curve to sub-pixel accuracy on average.
  static let coreCentroidMeanOffset = 0.75
  static let coreCentroidMaxOffset = 2.0
  /// Total light within 10 %.
  static let alphaMassRatio = 0.10
}

@main
struct WaveformRendererTests {
  static func pixels(_ texture: MTLTexture, device: MTLDevice) throws -> [UInt8] {
    guard let queue = device.makeCommandQueue(), let command = queue.makeCommandBuffer(),
      let buffer = device.makeBuffer(length: texture.width * texture.height * 4, options: .storageModeShared),
      let blit = command.makeBlitCommandEncoder()
    else { throw WaveformHarnessFailure("Readback unavailable") }
    blit.copy(
      from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
      sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1), to: buffer,
      destinationOffset: 0, destinationBytesPerRow: texture.width * 4,
      destinationBytesPerImage: texture.width * texture.height * 4)
    blit.endEncoding()
    command.commit()
    command.waitUntilCompleted()
    var bgra = Array(UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: UInt8.self), count: buffer.length))
    // Golden is RGBA; swap so every later comparison speaks one byte order.
    for offset in stride(from: 0, to: bgra.count, by: 4) { bgra.swapAt(offset, offset + 2) }
    return bgra
  }

  static func png(rgba: [UInt8], width: Int, height: Int, url: URL) throws {
    guard let provider = CGDataProvider(data: Data(rgba) as CFData),
      let image = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
      let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw WaveformHarnessFailure("PNG encoder unavailable") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw WaveformHarnessFailure("PNG write failed") }
  }

  static func layer(_ golden: GoldenCase) throws -> SceneRenderV2WaveformLayer {
    func argb(_ key: String) throws -> UInt32 {
      guard let value = golden.style[key] else { throw WaveformHarnessFailure("style.\(key) missing") }
      return value
    }
    return SceneRenderV2WaveformLayer(
      id: "waveform", opacity: golden.opacity,
      renderScales: harnessWaveformRenderScales,
      framesPerSecondByQuality: ["best": 24, "sustained": 20, "minimumFunctional": 16],
      sampleCountsByQuality: harnessWaveformSampleCounts,
      spectralNodeCountsByQuality: ["best": 15, "sustained": 13, "minimumFunctional": 9],
      glowPassesByQuality: harnessWaveformGlowPasses,
      idleVisibility: 0.64, zeroThreshold: 0.0005,
      maximumDisplacementHeightFraction: golden.maximumDisplacementHeightFraction,
      maximumDisplacementWidthFraction: golden.maximumDisplacementWidthFraction,
      outerARGB: try argb("outerArgb"), peakARGB: try argb("peakArgb"),
      hotCoreARGB: try argb("hotCoreArgb"), innerARGB: try argb("innerArgb"),
      coreARGB: try argb("coreArgb"),
      responseSeconds: [0.07, 0.42, 0.09, 0.48, 0.035, 0.20, 0.28, 0.90, 0.08, 0.38])
  }

  static func state(_ golden: GoldenCase, scale: Double = 1) -> SceneRenderV2WaveformState {
    let state = SceneRenderV2WaveformState(layerID: "waveform")
    state.inject(
      samples: golden.samples.map { Float($0 * scale) }, lineEnergy: golden.lineEnergy,
      peakAmplitude: golden.peakAmplitude * scale, impactLight: golden.impactLight,
      lineVisibility: golden.lineVisibility)
    return state
  }

  static func render(
    _ renderer: WaveformRendering, _ golden: GoldenCase, device: MTLDevice,
    quality: String = "best", scale: Double = 1
  ) throws -> [UInt8] {
    let width = Int((Double(golden.pixelWidth) * scale).rounded()) & ~1
    let height = Int((Double(golden.pixelHeight) * scale).rounded()) & ~1
    let texture = try autoreleasepool {
      try renderer.render(
        width: width, height: height, layer: try layer(golden), state: state(golden),
        quality: quality, pointScale: Float(golden.pointScale * scale), outputAllocator: nil)
    }
    return try pixels(texture, device: device)
  }

  /// `coreSpanLimit`: a column takes part in the centroid check only when the
  /// reference's saturated core (alpha >= 200) spans at most this many rows, i.e. the
  /// curve is locally flat there; on steep runs the column centroid measures the run,
  /// not the line position.
  static func compare(golden: [UInt8], test: [UInt8], width: Int, height: Int, coreSpanLimit: Double) -> ParityMetrics {
    var metrics = ParityMetrics()
    let count = width * height
    func alpha(_ image: [UInt8], _ index: Int) -> Int { Int(image[index * 4 + 3]) }
    var intersection8 = 0, union8 = 0, intersection64 = 0, union64 = 0, test8 = 0
    var unionCount = 0, unionAlphaSum = 0, unionOver32 = 0, unionRGBSum = 0, maxAlpha = 0
    var massGolden = 0, massTest = 0
    var columnGolden = [Double](repeating: 0, count: width), columnTest = columnGolden
    var rowGolden = [Double](repeating: 0, count: height), rowTest = rowGolden
    var centroidWeightGolden = [Double](repeating: 0, count: width), centroidMomentGolden = centroidWeightGolden
    var centroidWeightTest = centroidWeightGolden, centroidMomentTest = centroidWeightGolden
    var coreFirstRow = [Int](repeating: Int.max, count: width), coreLastRow = [Int](repeating: -1, count: width)
    for index in 0..<count {
      let a = alpha(golden, index), b = alpha(test, index)
      let x = index % width, y = index / width
      massGolden += a
      massTest += b
      columnGolden[x] += Double(a)
      columnTest[x] += Double(b)
      rowGolden[y] += Double(a)
      rowTest[y] += Double(b)
      if a >= 200 {
        centroidWeightGolden[x] += Double(a); centroidMomentGolden[x] += Double(a) * (Double(y) + 0.5)
        coreFirstRow[x] = min(coreFirstRow[x], y); coreLastRow[x] = max(coreLastRow[x], y)
      }
      if b >= 200 { centroidWeightTest[x] += Double(b); centroidMomentTest[x] += Double(b) * (Double(y) + 0.5) }
      let in8a = a > 8, in8b = b > 8, in64a = a > 64, in64b = b > 64
      if in8b { test8 += 1 }
      if in8a && in8b { intersection8 += 1 }
      if in8a || in8b { union8 += 1 }
      if in64a && in64b { intersection64 += 1 }
      if in64a || in64b { union64 += 1 }
      if in8a || in8b {
        unionCount += 1
        let difference = abs(a - b)
        unionAlphaSum += difference
        maxAlpha = max(maxAlpha, difference)
        if difference > 32 { unionOver32 += 1 }
        for channel in 0..<3 {
          unionRGBSum += abs(Int(golden[index * 4 + channel]) - Int(test[index * 4 + channel]))
        }
      }
    }
    metrics.iouAlpha8 = union8 == 0 ? 1 : Double(intersection8) / Double(union8)
    metrics.iouAlpha64 = union64 == 0 ? 1 : Double(intersection64) / Double(union64)
    metrics.containedInReference8 = test8 == 0 ? 1 : Double(intersection8) / Double(test8)
    func profile(_ reference: [Double], _ candidate: [Double], length: Double) -> (max: Double, relative: Double) {
      var maximum = 0.0, difference = 0.0, total = 0.0
      for index in reference.indices {
        let r = reference[index] / length, c = candidate[index] / length
        maximum = max(maximum, abs(r - c))
        difference += abs(r - c)
        total += r
      }
      return (maximum, total == 0 ? 0 : difference / total)
    }
    let column = profile(columnGolden, columnTest, length: Double(height))
    metrics.columnMeanMaxDiff = column.max
    metrics.columnMeanRelativeL1 = column.relative
    let row = profile(rowGolden, rowTest, length: Double(width))
    metrics.rowMeanMaxDiff = row.max
    metrics.rowMeanRelativeL1 = row.relative
    metrics.unionMeanAlphaDiff = unionCount == 0 ? 0 : Double(unionAlphaSum) / Double(unionCount)
    metrics.unionMaxAlphaDiff = maxAlpha
    metrics.unionOver32Fraction = unionCount == 0 ? 0 : Double(unionOver32) / Double(unionCount)
    metrics.unionMeanRGBDiff = unionCount == 0 ? 0 : Double(unionRGBSum) / Double(unionCount * 3)
    var centroidSum = 0.0, centroidMax = 0.0, centroidColumns = 0
    for x in 0..<width where centroidWeightGolden[x] > 0 && centroidWeightTest[x] > 0
      && Double(coreLastRow[x] - coreFirstRow[x] + 1) <= coreSpanLimit {
      let offset = abs(centroidMomentGolden[x] / centroidWeightGolden[x] - centroidMomentTest[x] / centroidWeightTest[x])
      centroidSum += offset
      centroidMax = max(centroidMax, offset)
      centroidColumns += 1
    }
    metrics.coreCentroidMeanOffset = centroidColumns == 0 ? .infinity : centroidSum / Double(centroidColumns)
    metrics.coreCentroidMaxOffset = centroidColumns == 0 ? .infinity : centroidMax
    metrics.coreColumnsCompared = centroidColumns
    metrics.alphaMassRatio = massGolden == 0 ? 0 : Double(massTest) / Double(massGolden)
    return metrics
  }

  static func verdict(_ metrics: ParityMetrics) -> [String] {
    var failures = [String]()
    if metrics.iouAlpha8 < ParityTolerance.iouAlpha8 { failures.append("IoU(a>8)") }
    if metrics.iouAlpha64 < ParityTolerance.iouAlpha64 { failures.append("IoU(a>64)") }
    if metrics.columnMeanMaxDiff > ParityTolerance.profileMaxDiff { failures.append("column profile max") }
    if metrics.columnMeanRelativeL1 > ParityTolerance.profileRelativeL1 { failures.append("column profile L1") }
    if metrics.rowMeanMaxDiff > ParityTolerance.profileMaxDiff { failures.append("row profile max") }
    if metrics.rowMeanRelativeL1 > ParityTolerance.profileRelativeL1 { failures.append("row profile L1") }
    if metrics.unionMeanAlphaDiff > ParityTolerance.unionMeanAlphaDiff { failures.append("union mean alpha") }
    if metrics.unionOver32Fraction > ParityTolerance.unionOver32Fraction { failures.append("union >32") }
    if metrics.coreCentroidMeanOffset > ParityTolerance.coreCentroidMeanOffset { failures.append("core centroid mean") }
    if metrics.coreCentroidMaxOffset > ParityTolerance.coreCentroidMaxOffset { failures.append("core centroid max") }
    if abs(metrics.alphaMassRatio - 1) > ParityTolerance.alphaMassRatio { failures.append("alpha mass") }
    return failures
  }

  /// Alpha along one column at offsets from the authored line: the cross-section a
  /// straight signal makes analytic, printed for golden and each renderer.
  static func crossSection(_ golden: GoldenCase, images: [(String, [UInt8])]) -> String {
    let width = golden.pixelWidth, height = golden.pixelHeight
    let x = width / 2
    let displacement = min(Double(height) * golden.maximumDisplacementHeightFraction,
                           Double(width) * golden.maximumDisplacementWidthFraction)
    let amplitude = golden.samples[golden.samples.count / 2]
    let line = Double(height) * 0.5 - amplitude * displacement
    let offsets = [-120, -96, -72, -48, -32, -24, -16, -12, -8, -6, -4, -3, -2, -1, 0, 1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 72, 96, 120]
    var text = "  cross-section at x=\(x), line y=\(String(format: "%.2f", line)) px (alpha 0-255 at row offsets)\n"
    text += "  offset  " + images.map { $0.0.padding(toLength: 10, withPad: " ", startingAt: 0) }.joined() + "\n"
    for offset in offsets {
      let y = Int((line + Double(offset)).rounded(.down))
      guard y >= 0, y < height else { continue }
      text += String(format: "  %+5d   ", offset)
      for (_, image) in images { text += "\(image[(y * width + x) * 4 + 3])".padding(toLength: 10, withPad: " ", startingAt: 0) }
      text += "\n"
    }
    return text
  }

  static func differenceImage(golden: [UInt8], test: [UInt8]) -> [UInt8] {
    var out = [UInt8](repeating: 255, count: golden.count)
    for index in stride(from: 0, to: golden.count, by: 4) {
      let difference = min(255, abs(Int(golden[index + 3]) - Int(test[index + 3])) * 4)
      let gained = test[index + 3] >= golden[index + 3]
      // Red: native brighter than Flutter; blue: dimmer. Grey background.
      out[index] = UInt8(gained ? min(255, 40 + difference) : 40)
      out[index + 1] = 40
      out[index + 2] = UInt8(gained ? 40 : min(255, 40 + difference))
    }
    return out
  }

  /// The fixed cost every renderer pays per frame on this path: a fresh private
  /// texture, a cleared render pass whose fragments all discard, commit and wait.
  /// Subtracting its median from a renderer's median isolates the shader's GPU work.
  final class FloorRenderer {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    init(device: MTLDevice) throws {
      self.device = device
      guard let queue = device.makeCommandQueue() else { throw WaveformHarnessFailure("floor queue") }
      self.queue = queue
      let library = try device.makeLibrary(source: """
        #include <metal_stdlib>
        using namespace metal;
        vertex float4 floorVertex(uint id [[vertex_id]]) {
          constexpr float2 p[6] = {float2(-1,-1),float2(1,-1),float2(-1,1),float2(-1,1),float2(1,-1),float2(1,1)};
          return float4(p[id],0,1);
        }
        fragment half4 floorFragment() { discard_fragment(); return half4(0); }
        """, options: nil)
      let descriptor = MTLRenderPipelineDescriptor()
      descriptor.vertexFunction = library.makeFunction(name: "floorVertex")
      descriptor.fragmentFunction = library.makeFunction(name: "floorFragment")
      descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
      pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }

    func render(width: Int, height: Int) throws {
      guard let texture = try SceneSurfaceNativeOutputAllocator.makeTexture(device: device, width: width, height: height, allocator: nil),
        let command = queue.makeCommandBuffer()
      else { throw WaveformHarnessFailure("floor target") }
      let pass = MTLRenderPassDescriptor()
      pass.colorAttachments[0].texture = texture
      pass.colorAttachments[0].loadAction = .clear
      pass.colorAttachments[0].storeAction = .store
      pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
      guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw WaveformHarnessFailure("floor encoder") }
      encoder.setRenderPipelineState(pipeline)
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
      encoder.endEncoding()
      command.commit()
      command.waitUntilCompleted()
    }
  }

  /// Every frame renders each renderer once, then the floor, so thermal and
  /// scheduling drift land on all of them alike.
  static func timeInterleaved(
    _ renderers: [(String, WaveformRendering)], floor: FloorRenderer, golden: GoldenCase,
    scale: Double, frames: Int, warmup: Int
  ) throws -> [String: [Double]] {
    let layer = try layer(golden)
    let state = state(golden, scale: scale)
    var durations = [String: [Double]]()
    for (label, _) in renderers { durations[label] = [] }
    durations["floor"] = []
    func measure(_ label: String, _ frame: Int, _ body: () throws -> Void) rethrows {
      let started = DispatchTime.now().uptimeNanoseconds
      try autoreleasepool(invoking: body)
      if frame >= warmup { durations[label]!.append(Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000) }
    }
    for frame in 0..<(warmup + frames) {
      for (label, renderer) in renderers {
        try measure(label, frame) {
          _ = try renderer.render(
            width: golden.pixelWidth, height: golden.pixelHeight, layer: layer, state: state,
            quality: "best", pointScale: Float(golden.pointScale), outputAllocator: nil)
        }
      }
      try measure("floor", frame) { try floor.render(width: golden.pixelWidth, height: golden.pixelHeight) }
    }
    return durations
  }

  static func statistics(_ values: [Double]) -> (median: Double, mean: Double, p90: Double) {
    let sorted = values.sorted()
    let median = sorted[sorted.count / 2]
    let mean = sorted.reduce(0, +) / Double(sorted.count)
    return (median, mean, sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.9))])
  }

  static func main() throws {
    setvbuf(stdout, nil, _IOLBF, 0)
    guard CommandLine.arguments.count == 4, let device = MTLCreateSystemDefaultDevice() else {
      throw WaveformHarnessFailure("usage: waveform-renderer-tests <golden-dir> <output-dir> <frames>; Metal device required")
    }
    let goldenDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
    let output = URL(fileURLWithPath: CommandLine.arguments[2])
    let frames = max(200, Int(CommandLine.arguments[3]) ?? 200)
    for folder in ["candidate", "baseline", "diff"] {
      try FileManager.default.createDirectory(at: output.appendingPathComponent(folder), withIntermediateDirectories: true)
    }
    print("Metal device: \(device.name) (registryID \(device.registryID))")

    var compileStarted = DispatchTime.now().uptimeNanoseconds
    let candidate = try WaveformRendererCandidate(device: device)
    print(String(format: "COMPILED candidate: Swift class instantiated, Metal library built with device.makeLibrary(source:) in %.1f ms", Double(DispatchTime.now().uptimeNanoseconds - compileStarted) / 1e6))
    var renderers: [(String, WaveformRendering)] = [("candidate", candidate)]
    #if HAS_BASELINE
    compileStarted = DispatchTime.now().uptimeNanoseconds
    let baseline = try WaveformRendererBaseline(device: device)
    print(String(format: "COMPILED baseline: Metal library built in %.1f ms", Double(DispatchTime.now().uptimeNanoseconds - compileStarted) / 1e6))
    renderers.append(("baseline", baseline))
    #endif

    let files = try FileManager.default.contentsOfDirectory(at: goldenDirectory, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    guard !files.isEmpty else { throw WaveformHarnessFailure("No golden JSON in \(goldenDirectory.path)") }
    var report = "# Waveform renderer parity against the Flutter painter (MusicWaveformPainter)\n"
    report += "device: \(device.name); goldens: \(goldenDirectory.path)\n"
    report += "Metrics: alpha = accumulated coverage of all passes (premultiplied RGBA both sides).\n"
    report += "Tolerances (quality best vs Flutter): IoU(a>8)>=\(ParityTolerance.iouAlpha8) IoU(a>64)>=\(ParityTolerance.iouAlpha64) profile max<=\(ParityTolerance.profileMaxDiff) relL1<=\(ParityTolerance.profileRelativeL1) union mean<=\(ParityTolerance.unionMeanAlphaDiff) >32<=\(ParityTolerance.unionOver32Fraction) centroid mean<=\(ParityTolerance.coreCentroidMeanOffset)px max<=\(ParityTolerance.coreCentroidMaxOffset)px mass within \(ParityTolerance.alphaMassRatio)\n\n"
    var json = [String: Any]()
    var failed = [String]()
    for file in files {
      let golden = try JSONDecoder().decode(GoldenCase.self, from: Data(contentsOf: file))
      let reference = [UInt8](try Data(contentsOf: file.deletingPathExtension().appendingPathExtension("rgba")))
      guard reference.count == golden.pixelWidth * golden.pixelHeight * 4 else {
        throw WaveformHarnessFailure("\(golden.name): golden rgba size mismatch")
      }
      report += "## \(golden.name)  \(golden.pixelWidth)x\(golden.pixelHeight) px, logical \(golden.logicalWidth)x\(golden.logicalHeight), pointScale \(String(format: "%.4f", golden.pointScale)), peak \(golden.peakAmplitude)\n"
      var sections = [(String, [UInt8])]([("flutter", reference)])
      var caseJSON = [String: Any]()
      for (label, renderer) in renderers {
        let image = try render(renderer, golden, device: device)
        try png(rgba: image, width: golden.pixelWidth, height: golden.pixelHeight,
                url: output.appendingPathComponent("\(label)/\(golden.name).png"))
        try Data(image).write(to: output.appendingPathComponent("\(label)/\(golden.name).rgba"))
        let metrics = compare(golden: reference, test: image, width: golden.pixelWidth, height: golden.pixelHeight,
                              coreSpanLimit: 5 * golden.pointScale + 2)
        let failures = verdict(metrics)
        let status = failures.isEmpty ? "PASS" : "FAIL(\(failures.joined(separator: ", ")))"
        report += "  \(label.padding(toLength: 10, withPad: " ", startingAt: 0)) \(status)\n    \(metrics.summary)\n"
        print("\(failures.isEmpty ? "PASS" : "FAIL") parity \(label) \(golden.name): \(metrics.summary)")
        if label == "candidate" && !failures.isEmpty { failed.append(golden.name) }
        caseJSON[label] = metrics.json.merging(["failures": failures]) { $1 }
        sections.append((label, image))
        if label == "candidate" {
          try png(rgba: differenceImage(golden: reference, test: image), width: golden.pixelWidth,
                  height: golden.pixelHeight, url: output.appendingPathComponent("diff/\(golden.name).png"))
        }
      }
      if golden.signal == "straight" { report += crossSection(golden, images: sections) }
      // Shared qualities have no Flutter counterpart (V1 always renders `best`) and
      // drop glow passes by design (4 and 3 of 5). They must compile, render, never
      // light pixels outside the `best` footprint of the same reduced target, never
      // add light, and keep the line where `best` draws it.
      for quality in ["sustained", "minimumFunctional"] {
        guard let renderScale = harnessWaveformRenderScales[quality] else { continue }
        let bestReduced = try render(candidate, golden, device: device, quality: "best", scale: renderScale)
        let reduced = try render(candidate, golden, device: device, quality: quality, scale: renderScale)
        let width = Int((Double(golden.pixelWidth) * renderScale).rounded()) & ~1
        let height = Int((Double(golden.pixelHeight) * renderScale).rounded()) & ~1
        try png(rgba: reduced, width: width, height: height,
                url: output.appendingPathComponent("candidate/\(golden.name).\(quality).png"))
        let metrics = compare(golden: bestReduced, test: reduced, width: width, height: height,
                              coreSpanLimit: 5 * golden.pointScale * renderScale + 2)
        let ok = metrics.containedInReference8 >= 0.98 && metrics.coreCentroidMeanOffset <= 1.0
          && metrics.alphaMassRatio > 0.15 && metrics.alphaMassRatio <= 1.02
        report += "  quality \(quality) @\(width)x\(height) vs best (same target) \(ok ? "OK" : "CHECK")\n    \(metrics.summary)\n"
        print("\(ok ? "PASS" : "FAIL") quality \(quality) \(golden.name): \(metrics.summary)")
        if !ok { failed.append("\(golden.name).\(quality)") }
        caseJSON[quality] = metrics.json
      }
      report += "\n"
      json[golden.name] = caseJSON
    }
    try report.write(to: output.appendingPathComponent("parity.txt"), atomically: true, encoding: .utf8)
    try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
      .write(to: output.appendingPathComponent("parity.json"))

    // Cost: wall-clock of render() (texture + encode + GPU + waitUntilCompleted) on
    // this Mac. The floor pass isolates what the shader itself costs.
    let floor = try FloorRenderer(device: device)
    var cost = "# Waveform renderer cost on \(device.name)\n"
    cost += "wall-clock per frame in ms: fresh private texture + encode + GPU + waitUntilCompleted (allocator nil, the shared V2 path).\n"
    cost += "floor = same pass with every fragment discarded: the fixed cost both renderers pay; 'gpu' = median - floor median.\n"
    cost += "\(frames) timed frames after 20 warm-up frames; each frame runs candidate, baseline and floor back to back.\n"
    cost += "Mac GPU (\(device.name)) != iPhone/iPad GPU: ratios transfer, absolute times do not.\n\n"
    let costCases = files.compactMap { file -> GoldenCase? in
      guard let golden = try? JSONDecoder().decode(GoldenCase.self, from: Data(contentsOf: file)) else { return nil }
      return golden.signal == "sine_peaks" && (golden.viewport.contains("3x") || golden.viewport.contains("ipad")) ? golden : nil
    }
    var costJSON = [String: Any]()
    for golden in costCases {
      for amplitude in [1.0, 1.0 / golden.peakAmplitude] {
        let samples = try timeInterleaved(renderers, floor: floor, golden: golden, scale: amplitude, frames: frames, warmup: 20)
        let peak = golden.peakAmplitude * amplitude
        let title = String(format: "%@  %dx%d px  peak %.2f (band %@)", golden.name, golden.pixelWidth, golden.pixelHeight, peak, peak >= 0.999 ? "full" : "partial")
        cost += "## \(title)\n"
        let floorStatistics = statistics(samples["floor"]!)
        cost += String(format: "  %-10@ median %.3f ms  mean %.3f ms  p90 %.3f ms\n", "floor", floorStatistics.median, floorStatistics.mean, floorStatistics.p90)
        var line = [String: (median: Double, mean: Double, p90: Double)]()
        var entry: [String: Any] = ["floorMedianMs": floorStatistics.median]
        for (label, _) in renderers {
          let s = statistics(samples[label]!)
          line[label] = s
          cost += String(format: "  %-10@ median %.3f ms  mean %.3f ms  p90 %.3f ms  gpu~%.3f ms\n", label, s.median, s.mean, s.p90, s.median - floorStatistics.median)
          entry[label + "MedianMs"] = s.median
          entry[label + "GpuMs"] = s.median - floorStatistics.median
        }
        if let c = line["candidate"], let b = line["baseline"] {
          let gpuRatio = (c.median - floorStatistics.median) / max(b.median - floorStatistics.median, 0.001)
          cost += String(format: "  ratio candidate/baseline: wall median %.2fx  gpu-attributable %.2fx\n", c.median / b.median, gpuRatio)
          entry["wallRatio"] = c.median / b.median
          entry["gpuRatio"] = gpuRatio
        }
        cost += "\n"
        costJSON[title] = entry
      }
    }
    try JSONSerialization.data(withJSONObject: costJSON, options: [.prettyPrinted, .sortedKeys])
      .write(to: output.appendingPathComponent("cost.json"))
    try cost.write(to: output.appendingPathComponent("cost.txt"), atomically: true, encoding: .utf8)
    print(cost)
    if !failed.isEmpty {
      print("FAILED cases: \(failed.joined(separator: ", "))")
      exit(2)
    }
    print("ALL PARITY GATES PASSED")
  }
}
