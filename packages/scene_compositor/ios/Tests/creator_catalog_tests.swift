import Foundation
import CoreGraphics
import Metal

@main
enum CreatorCatalogTests {
  static func main() throws {
    checkVectorGeometry()
    if CommandLine.arguments.count >= 2 {
      try smokeAuthoredCatalog(path: CommandLine.arguments[1])
      return
    }
    let entry: [String: Any] = [
      "id": "test", "name": "Test", "programId": "creator_test", "role": "background",
      "reactivity": "optional", "framesPerSecond": 30, "seed": 0xffa12345,
      "colors": [0xff336699, 0xff000000, 0xffffffff, 0xff00ff00],
      "controls": ["intensity": 1, "speed": 1, "detail": 1, "glow": 1],
      "shaderSource": """
      vec4 paintVisual(vec2 uv, CreatorFrame f) {
        vec2 wrapped = mod(vec2(-1.0, 5.0), 4.0);
        bool exactSeed = f.seedLow == 9029.0 && f.seedHigh == 65441.0;
        bool portableMod = wrapped.x == 3.0 && wrapped.y == 1.0 && mod(-5.0, 4.0) == 3.0;
        return exactSeed && portableMod ? vec4(f.energy, f.bass, f.pulse, 1.0) : vec4(0.0);
      }
      """,
    ]
    func data(_ entries: [[String: Any]]) throws -> Data {
      try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "visuals": entries])
    }
    var inert = entry
    inert["id"] = "inert"; inert["programId"] = "creator_inert"
    inert["shaderSource"] = "vec4 paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.2, 0.4, 0.6, 1.0); }"
    var ambientEntry = inert
    ambientEntry["id"] = "ambient"; ambientEntry["programId"] = "creator_ambient"
    ambientEntry["reactivity"] = "none"
    var musicEntry = entry
    musicEntry["id"] = "music"; musicEntry["programId"] = "creator_music"
    musicEntry["reactivity"] = "music"
    let encoded = try data([entry, inert, ambientEntry, musicEntry])
    let parsed = try SceneCreatorCatalog.decode(encoded)
    precondition(parsed.count == 4 && parsed["creator_test"]?.shader?.floatCount == 32)
    do { _ = try SceneCreatorCatalog.decode(data([entry, entry])); preconditionFailure("Duplicate accepted") }
    catch {}
    func many(_ count: Int) -> [[String: Any]] {
      (0..<count).map { i -> [String: Any] in
        var item = entry
        item["id"] = "test_\(i)"
        item["programId"] = "creator_test_\(i)"
        return item
      }
    }
    // El antiguo tope de 256 ya no existe: sólo se rechaza un catálogo desbocado.
    // `precondition` takes a non-throwing autoclosure: decode first.
    let threeHundred = try SceneCreatorCatalog.decode(data(many(300)))
    precondition(threeHundred.count == 300)
    do {
      _ = try SceneCreatorCatalog.decode(data(many(SceneCreatorCatalog.maximumCatalogVisuals + 1)))
      preconditionFailure("Over-limit visuals accepted")
    } catch {}
    var invalid = entry
    invalid["shaderSource"] = "#include <another_runtime>"
    do { _ = try SceneCreatorCatalog.decode(data([invalid])); preconditionFailure("Extra runtime accepted") }
    catch {}
    invalid = entry; invalid["seed"] = -1
    do { _ = try SceneCreatorCatalog.decode(data([invalid])); preconditionFailure("Invalid seed accepted") }
    catch {}
    let lados: [String: Any] = ["id": "lados", "label": "Lados", "kind": "steps", "min": 3, "max": 8, "value": 4]
    let tono: [String: Any] = ["id": "tono", "label": "Tono", "kind": "choice", "min": 0, "max": 1, "value": 0,
      "options": ["Azul", "Amarillo"]]
    invalid = entry; invalid["modifiers"] = [lados]
    do { _ = try SceneCreatorCatalog.decode(data([invalid])); preconditionFailure("Shader visual declared modifiers") }
    catch {}
    let absent = try SceneCreatorCatalog.modifiers(nil), declared = try SceneCreatorCatalog.modifiers([lados, tono])
    precondition(absent.isEmpty && declared.map(\.id) == ["lados", "tono"])
    for bad: [[String: Any]] in [[], [lados, lados], [lados.merging(["id": "speed"]) { $1 }],
      [lados.merging(["value": 4.5]) { $1 }], [lados.merging(["extra": 1]) { $1 }],
      [tono.merging(["max": 2]) { $1 }], [lados.merging(["kind": "toggle"]) { $1 }]] {
      do { _ = try SceneCreatorCatalog.modifiers(bad); preconditionFailure("Invalid modifiers accepted: \(bad)") }
      catch {}
    }
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try encoded.write(to: path)
    defer { try? FileManager.default.removeItem(at: path) }
    SceneCreatorCatalog.loadBundledIfNeeded(assetPath: path.path)
    precondition(SceneCreatorShaderState(program: "creator_test", options: ["unexpected": 1], mode: nil, reactive: true) == nil)
    let state = SceneCreatorShaderState(program: "creator_test", options: [:], mode: nil, reactive: true)!
    let idle = SceneRenderSignalEventV2(serial: 0, active: false, timestampMicros: 0, strength: 0, band: .none)
    let hit = SceneRenderSignalEventV2(serial: 1, active: true, timestampMicros: 0, strength: 0.8, band: .low)
    let frame = SceneRenderSignalFrameV2(sessionId: 7, sequence: 1, audioTimestampMicros: 1,
      available: true, fresh: true, musicActive: true, tonalAvailable: false,
      dynamics: [0.1, 0.2, 0.3, 0.4, 0.5, 0], channels: [0.4, 0.5, 0.6, 0.7],
      spectrumSummary: [Float](repeating: 0, count: 7), instantSpectrum: [Float](repeating: 0, count: 31),
      smoothedSpectrum: [Float](repeating: 0, count: 31), semantics: [Float](repeating: 0, count: 6),
      rhythm: [120, 0.25, 0.8, 0.9], onsets: [0, 0, 0, 0], tonal: [0, 0, 0],
      impact: hit, accent: idle, beat: idle, flash: idle)
    precondition(state.consume(frame))
    let values = state.uniforms(size: CGSize(width: 16, height: 16), hostTime: 1, reducedMotion: false)
    precondition(values.count == 32 && values[4] == 0.2 && values[5] == 0.4 && values[9] == 0.8)
    precondition(values[10] == 0.25 && values[11] == 120 && values[3].bitPattern == 0xffa12345)
    _ = state.consume(frame)
    precondition(state.uniforms(size: CGSize(width: 16, height: 16), hostTime: 1.03, reducedMotion: false)[9] == 0,
      "Repeated active serial fired twice")
    let pausedTime = state.uniforms(size: CGSize(width: 16, height: 16), hostTime: 1.06, reducedMotion: false)[2]
    state.setPlaying(false, hostTime: 1.06)
    let paused = state.uniforms(size: CGSize(width: 16, height: 16), hostTime: 20, reducedMotion: false)
    precondition(paused[2] == pausedTime && paused[4] == 0)
    let ambient = SceneCreatorShaderState(program: "creator_test", options: [:], mode: nil, reactive: false)!
    _ = ambient.consume(frame)
    precondition(ambient.uniforms(size: CGSize(width: 16, height: 16), hostTime: 1, reducedMotion: false)[4..<12].allSatisfy { $0 == 0 })

    guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Metal device is required for renderer verification") }
    let frameQueue = device.makeCommandQueue()!
    let allocation = device.makeBuffer(length: 4096, options: .storageModeShared)!
    let gpuFrame = try SceneCatalogFrameCommand(queue: frameQueue)
    try gpuFrame.retain(allocation)
    let retained = gpuFrame.retainedBytes
    try gpuFrame.retain(allocation)
    precondition(gpuFrame.retainedBytes == retained && retained == allocation.allocatedSize)
    let constrained = try SceneCatalogFrameCommand(queue: frameQueue, budgetBytes: retained - 1)
    do { try constrained.retain(allocation); preconditionFailure("Queued frame exceeded its memory budget") }
    catch {}
    try gpuFrame.complete()
    precondition(gpuFrame.command.status == .completed)
    print("PASS frame commands: completion, resource deduplication and bounded queued memory")
    let renderer = try SceneCatalogShaderRenderer(device: device)
    try renderer.prepare(program: "creator_test")
    let texture = try renderer.render(program: "creator_test", uniforms: values, width: 16, height: 16)
    let buffer = device.makeBuffer(length: 16 * 16 * 4, options: .storageModeShared)!
    let command = device.makeCommandQueue()!.makeCommandBuffer()!
    let blit = command.makeBlitCommandEncoder()!
    blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
      sourceSize: MTLSize(width: 16, height: 16, depth: 1), to: buffer, destinationOffset: 0,
      destinationBytesPerRow: 64, destinationBytesPerImage: 1024)
    blit.endEncoding(); command.commit(); command.waitUntilCompleted()
    precondition(command.status == .completed)
    let pixel = buffer.contents().assumingMemoryBound(to: UInt8.self)
    precondition(abs(Int(pixel[0]) - 204) <= 1 && abs(Int(pixel[1]) - 102) <= 1 && abs(Int(pixel[2]) - 51) <= 1 && pixel[3] == 255,
      "CreatorFrame Metal ABI or output color is incorrect")
    print("PASS modifiers: declarations validated; legacy shaders cannot declare them")
    print("PASS creator catalog validation, exact signal mapping, event deduplication, pause, nonreactive state, Metal uniform ABI and output pixels")
    for id in ["creator_test", "creator_music", "creator_ambient"] {
      try verifyReactivity(programID: id, program: parsed[id]!, renderer: renderer, device: device)
    }
    do {
      try verifyReactivity(programID: "creator_inert", program: parsed["creator_inert"]!, renderer: renderer, device: device)
      preconditionFailure("A shader that ignores music was accepted as reactive")
    } catch let error as SceneCreatorCatalog.CatalogError {
      precondition(error.code.hasPrefix("reaction_not_demonstrated"), error.code)
      print("PASS rejects a visual falsely declared reactive")
    }
  }

  static func smokeAuthoredCatalog(path: String) throws {
    let admission = CommandLine.arguments.contains("--admission")
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let catalog = try SceneCreatorCatalog.decode(data)
    precondition(!catalog.isEmpty, "Authored catalog must contain an example")
    SceneCreatorCatalog.loadBundledIfNeeded(assetPath: path)
    guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Metal device is required for authored shader verification") }
    let renderer = try SceneCatalogShaderRenderer(device: device)
    for programID in catalog.keys.sorted() {
      let program = catalog[programID]!
      try renderer.prepare(program: programID)
      guard let state = SceneCreatorShaderState(program: programID, options: [:], mode: nil,
        reactive: program.reactivity != "none") else { fatalError("Authored program state rejected: \(programID)") }
      for size in [CGSize(width: 128, height: 192), CGSize(width: 192, height: 128)] {
        let values = state.uniforms(size: size, hostTime: 1, reducedMotion: false)
        let texture = try renderer.render(program: programID, uniforms: values,
          width: Int(size.width), height: Int(size.height))
        let bytes = readPixels(texture: texture, device: device)
        var visiblePixels = 0
        var coloredPixels = 0
        var distinctColors = Set<UInt32>()
        for offset in stride(from: 0, to: bytes.count, by: 4) {
          let blue = bytes[offset], green = bytes[offset + 1], red = bytes[offset + 2], alpha = bytes[offset + 3]
          if alpha > 0 { visiblePixels += 1 }
          if max(blue, max(green, red)) > 0 { coloredPixels += 1 }
          distinctColors.insert(UInt32(blue) | UInt32(green) << 8 | UInt32(red) << 16 | UInt32(alpha) << 24)
        }
        let pixelCount = Int(size.width * size.height)
        if !admission {
          precondition(visiblePixels > pixelCount / 8, "Authored shader is transparent: \(programID)")
          precondition(coloredPixels > pixelCount / 8, "Authored shader is black: \(programID)")
          precondition(distinctColors.count > 16, "Authored shader has no spatial detail: \(programID)")
        }
        if admission && program.role == "background" {
          precondition(stride(from: 3, to: bytes.count, by: 4).allSatisfy { bytes[$0] == 255 }, "Background shader must be opaque")
        }
        print("PASS authored \(programID): \(Int(size.width))x\(Int(size.height)), \(visiblePixels) visible pixels, \(distinctColors.count) distinct BGRA values")
      }
      try verifyReactivity(programID: programID, program: program, renderer: renderer, device: device)
    }
    print("PASS all \(catalog.count) bundled authored shaders compile and render Metal output")
  }

  /// Synthetic contract inputs, never advertised as recordings of a sensor.
  /// Freeze shader time so ambient motion cannot masquerade as music response.
  static func verifyReactivity(programID: String, program: SceneCreatorCatalog.Program,
      renderer: SceneCatalogShaderRenderer, device: MTLDevice) throws {
    try renderer.prepare(program: programID)
    let size = CGSize(width: 96, height: 128)
    let reactive = program.reactivity != "none"
    let idle = SceneRenderSignalEventV2(serial: 0, active: false, timestampMicros: 0, strength: 0, band: .none)
    func signal(_ strength: Float, available: Bool = true, music: Bool = true) -> SceneRenderSignalFrameV2 {
      let hit = SceneRenderSignalEventV2(serial: 1, active: true, timestampMicros: 1,
        strength: strength, band: .low)
      return SceneRenderSignalFrameV2(sessionId: 1, sequence: 1, audioTimestampMicros: 1,
        available: available, fresh: true, musicActive: music, tonalAvailable: false,
        dynamics: [strength, strength, strength, strength, strength, 0],
        channels: [strength, strength * 0.8, strength * 0.6, strength * 0.9],
        spectrumSummary: [Float](repeating: 0, count: 7), instantSpectrum: [Float](repeating: 0, count: 31),
        smoothedSpectrum: [Float](repeating: 0, count: 31), semantics: [Float](repeating: 0, count: 6),
        rhythm: [90 + 60 * strength, strength, strength, strength], onsets: [0, 0, 0, 0],
        tonal: [0, 0, 0], impact: hit, accent: idle, beat: idle, flash: idle)
    }
    func pixels(time: Float, input: SceneRenderSignalFrameV2?, enabled: Bool) throws -> [UInt8] {
      guard let state = SceneCreatorShaderState(program: programID, options: [:], mode: nil,
        reactive: enabled) else { throw SceneCreatorCatalog.CatalogError("reactivity_mode_rejected: \(programID)") }
      if let input { precondition(state.consume(input)) }
      var values = state.uniforms(size: size, hostTime: 0, reducedMotion: false)
      // This is a controlled render probe, not a second playback clock.
      values[2] = time
      if !enabled || input?.available != true || input?.musicActive != true {
        precondition(values[4..<12].allSatisfy { $0 == 0 }, "Music gate leaked signal values")
      }
      let texture = try renderer.render(program: programID, uniforms: values,
        width: Int(size.width), height: Int(size.height))
      return readPixels(texture: texture, device: device)
    }
    var changedWithMusic = false
    for time: Float in [0, 2.5, 7] {
      let neutral = try pixels(time: time, input: nil, enabled: reactive)
      for strength: Float in [0.25, 0.8] {
        let music = try pixels(time: time, input: signal(strength), enabled: reactive)
        if reactive { changedWithMusic = changedWithMusic || music != neutral }
        else { precondition(music == neutral, "Nonreactive visual changed with music") }
        let silence = try pixels(time: time, input: signal(strength, music: false), enabled: reactive)
        let unavailable = try pixels(time: time, input: signal(strength, available: false), enabled: reactive)
        precondition(silence == neutral && unavailable == neutral, "Unauthorized audio affected the visual")
        if program.reactivity == "optional" {
          let disabled = try pixels(time: time, input: signal(strength), enabled: false)
          precondition(disabled == neutral, "Disabling music did not restore ambient behavior")
        }
      }
    }
    if reactive && !changedWithMusic {
      throw SceneCreatorCatalog.CatalogError(
        "reaction_not_demonstrated: \(programID): figura como reactivo pero no cambia en las pruebas musicales. " +
        "Haz que el dibujo use las señales de la plantilla, o elige reactivity: none si es ambiental.")
    }
    print("PASS behavior \(programID): \(program.reactivity), synthetic same-time music/silence/unavailable/off probes")
  }

  // Frozen pre-optimization geometry: catches changes in winding order,
  // curve subdivision, Float conversion and device scaling.
  static func checkVectorGeometry() {
    var contourScratch = [CGPoint(x: -1234, y: 5678)]
    let strokes = SceneCatalogVectorCanvas.StrokeGeometryCache()
    for i in 0..<80 {
      let path = CGMutablePath()
      let n = Double(i + 1)
      path.move(to: CGPoint(x: n * 0.37, y: -n * 0.21))
      path.addCurve(to: CGPoint(x: n * 1.73, y: n * 0.91),
        control1: CGPoint(x: -n * 0.83, y: n * 2.13),
        control2: CGPoint(x: n * 2.71, y: -n * 1.33))
      path.addQuadCurve(to: CGPoint(x: n * 0.23, y: n * 1.17),
        control: CGPoint(x: n * 1.47, y: n * 3.19))
      path.closeSubpath()
      path.addEllipse(in: CGRect(x: -n, y: n * 0.1, width: n * 0.71, height: n * 1.17))
      path.addRect(CGRect(x: n * 0.13, y: n * 0.17, width: n * 0.91, height: n * 0.77))
      path.move(to: CGPoint(x: n, y: n))
      path.addLine(to: CGPoint(x: n * 1.31, y: n * 1.97))
      path.addLine(to: CGPoint(x: n * 0.57, y: -n * 0.83))
      let stroke = path.copy(strokingWithWidth: 0.11 + n * 0.03,
        lineCap: .round, lineJoin: .round, miterLimit: 4)
      for cap: CGLineCap in [.butt, .round, .square] {
        for join: CGLineJoin in [.miter, .round, .bevel] {
          let expected = path.copy(strokingWithWidth: 0.11 + n * 0.03, lineCap: cap, lineJoin: join, miterLimit: 4)
          let first = strokes.geometry(path, width: 0.11 + n * 0.03, cap: cap, join: join)
          let repeated = strokes.geometry(path, width: 0.11 + n * 0.03, cap: cap, join: join)
          precondition(first.outline == expected && repeated.outline === first.outline,
            "Stroke reuse changed cap, join or geometry")
        }
      }
      for candidate in [path as CGPath, stroke] {
        for tolerance in [0.02, 0.08, 0.4] {
          let original = referenceTriangles(path: candidate, tolerance: tolerance)
          for scale: SIMD2<Float> in [SIMD2(1, 1), SIMD2(1.08, 1.08), SIMD2(0.5, 2.7)] {
            let expected = original.map { $0 * scale }
            let sentinel = SIMD2<Float>(-999, 999)
            var actual = [sentinel]
            SceneCatalogVectorRenderer.appendTriangles(path: candidate, tolerance: tolerance,
              scale: scale, into: &actual)
            precondition(actual.first == sentinel && actual.count == expected.count + 1)
            var reused = [sentinel]
            SceneCatalogVectorRenderer.appendTriangles(path: candidate, tolerance: tolerance,
              scale: scale, into: &reused, contour: &contourScratch)
            precondition(contourScratch.isEmpty && reused.count == actual.count)
            for (a, b) in zip(reused, actual) {
              precondition(a.x.bitPattern == b.x.bitPattern && a.y.bitPattern == b.y.bitPattern,
                "Retained contour capacity changed the geometry")
            }
            for (a, b) in zip(actual.dropFirst(), expected) {
              precondition(a.x.bitPattern == b.x.bitPattern && a.y.bitPattern == b.y.bitPattern,
                "Vector geometry changed during allocation optimization")
            }
          }
        }
      }
    }
    let mutable = CGMutablePath(); mutable.addRect(CGRect(x: 0, y: 0, width: 10, height: 10))
    let original = strokes.geometry(mutable, width: 2, cap: .round, join: .round)
    mutable.move(to: CGPoint(x: 2, y: 2)); mutable.addLine(to: CGPoint(x: 8, y: 8))
    let changed = strokes.geometry(mutable, width: 2, cap: .round, join: .round)
    precondition(original.source != mutable && changed.outline == mutable.copy(strokingWithWidth: 2,
      lineCap: .round, lineJoin: .round, miterLimit: 4), "Mutable equal-bounds path reused stale stroke")
    let collision = CGMutablePath(); collision.move(to: CGPoint(x: 0, y: 0))
    collision.addLine(to: CGPoint(x: 10, y: 10)); collision.addLine(to: CGPoint(x: 0, y: 10)); collision.closeSubpath()
    precondition(collision.boundingBox == mutable.boundingBox)
    let other = strokes.geometry(collision, width: 2, cap: .round, join: .round)
    precondition(other.outline == collision.copy(strokingWithWidth: 2, lineCap: .round, lineJoin: .round, miterLimit: 4),
      "Equal bounds are not equal geometry")
    print("PASS stroke reuse: caps, joins, bounded retention, mutation and equal-bounds collisions")
    print("PASS vector geometry: 1440 curved/compound/stroked/scaled cases, bit-for-bit")
    for count in [255, 256, 513, 4096] {
      let path = CGMutablePath()
      path.move(to: .zero)
      for index in 1...count {
        path.addLine(to: CGPoint(x: Double(index) * 0.17, y: sin(Double(index) * 0.13) * 7))
      }
      path.closeSubpath()
      path.move(to: CGPoint(x: 2, y: 3))
      path.addLine(to: CGPoint(x: 5, y: 8))
      path.addLine(to: CGPoint(x: 13, y: 21))
      path.closeSubpath()
      path.move(to: CGPoint(x: 31, y: 37))
      path.addLine(to: CGPoint(x: 41, y: 43))
      let scale = SIMD2<Float>(1.08, 2.7)
      let expected = referenceTriangles(path: path, tolerance: 0.08).map { $0 * scale }
      var actual: [SIMD2<Float>] = []
      SceneCatalogVectorRenderer.appendTriangles(path: path, tolerance: 0.08,
        scale: scale, into: &actual, contour: &contourScratch)
      precondition(contourScratch.isEmpty && actual.count == expected.count)
      for (a, b) in zip(actual, expected) {
        precondition(a.x.bitPattern == b.x.bitPattern && a.y.bitPattern == b.y.bitPattern,
          "Contour growth or reuse changed the geometry")
      }
    }
    print("PASS vector point storage: allocation growth and reuse preserve dense contours")
  }

  static func referenceTriangles(path: CGPath, tolerance: Double) -> [SIMD2<Float>] {
    var polygons: [[CGPoint]] = []
    var current: [CGPoint] = []
    func flush() { if current.count > 2 { polygons.append(current) }; current.removeAll(keepingCapacity: true) }
    func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
      let dx = b.x - a.x, dy = b.y - a.y
      let length = hypot(dx, dy)
      return length < 1e-12 ? hypot(p.x - a.x, p.y - a.y) : abs(dy * p.x - dx * p.y + b.x * a.y - b.y * a.x) / length
    }
    func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
    func cubic(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint, _ depth: Int) {
      if depth >= 16 || max(distance(b, a, d), distance(c, a, d)) <= tolerance {
        current.append(d); return
      }
      let ab = midpoint(a, b), bc = midpoint(b, c), cd = midpoint(c, d)
      let abc = midpoint(ab, bc), bcd = midpoint(bc, cd), middle = midpoint(abc, bcd)
      cubic(a, ab, abc, middle, depth + 1); cubic(middle, bcd, cd, d, depth + 1)
    }
    path.applyWithBlock { pointer in
      let element = pointer.pointee
      switch element.type {
      case .moveToPoint: flush(); current.append(element.points[0])
      case .addLineToPoint: current.append(element.points[0])
      case .addQuadCurveToPoint:
        let a = current.last ?? .zero, b = element.points[0], c = element.points[1]
        cubic(a, CGPoint(x: a.x + (b.x - a.x) * 2 / 3, y: a.y + (b.y - a.y) * 2 / 3),
              CGPoint(x: c.x + (b.x - c.x) * 2 / 3, y: c.y + (b.y - c.y) * 2 / 3), c, 0)
      case .addCurveToPoint: cubic(current.last ?? .zero, element.points[0], element.points[1], element.points[2], 0)
      case .closeSubpath: flush()
      @unknown default: preconditionFailure("Unrepresented CGPath element")
      }
    }
    flush()
    var result: [SIMD2<Float>] = []
    for polygon in polygons {
      let origin = polygon[0]
      for index in 1..<(polygon.count - 1) {
        for point in [origin, polygon[index], polygon[index + 1]] {
          result.append(SIMD2(Float(point.x), Float(point.y)))
        }
      }
    }
    return result
  }

  static func readPixels(texture: MTLTexture, device: MTLDevice) -> [UInt8] {
    let byteCount = texture.width * texture.height * 4
    let buffer = device.makeBuffer(length: byteCount, options: .storageModeShared)!
    let command = device.makeCommandQueue()!.makeCommandBuffer()!
    let blit = command.makeBlitCommandEncoder()!
    blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
      sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1), to: buffer,
      destinationOffset: 0, destinationBytesPerRow: texture.width * 4, destinationBytesPerImage: byteCount)
    blit.endEncoding(); command.commit(); command.waitUntilCompleted()
    precondition(command.status == .completed, "Authored output pixel readback failed")
    return Array(UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: UInt8.self), count: byteCount))
  }
}
