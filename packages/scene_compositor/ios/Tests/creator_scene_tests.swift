import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@main
struct CreatorSceneTests {
  static func continuity(_ program: SceneCreatorCatalog.Program, device: MTLDevice) throws {
    func parameters(_ reactive: Bool, width: Int = 320, seed: Int = 42) -> [String: Any] {
      let transform: [String: Any] = ["width":1,"height":1,"offsetX":0,"offsetY":0,"scale":1,"rotation":0,"flipped":false]
      var variants = [String: Any]()
      for level in ["best", "sustained", "minimumFunctional"] {
        variants[level] = ["level":level,"parameterOverrides":[:],"resourceOverrides":[:],
          "renderScale":1,"framesPerSecond":program.framesPerSecond] as [String: Any]
      }
      let node: [String: Any] = ["nodeType":"effect.catalogProgram","nodeVersion":1,
        "parameters":["programId":"creator_"+program.id,"audioReactive":reactive,"seed":seed,"options":["speed":width == 320 ? 0.7 : 0.9,"Music Reactive":reactive]],
        "resourceSlots":[],"signalBindings":reactive ? [["signal":"frame.v2","target":"runtime.signalFrame","scale":1,"bias":0]] : [],
        "transitionStrategy":"stateReplay","qualityVariants":variants]
      return ["resolvedResourcePaths":[:],"logicalWidth":width,"logicalHeight":568,
        "document":["schemaVersion":2,"sceneId":"creator_"+program.id,"layers":[[
          "id":program.id,"role":program.role,"opacity":1,"playbackRate":1,"blendMode":"sourceOver",
          "alphaMode":"normal","fallbackPolicy":"continuousCompatibility","transform":transform,
          "frameRateBinding":"preferred","preferredFramesPerSecond":program.framesPerSecond,"node":node]]]]
    }
    let enabled = program.reactivity != "none"
    let initial = parameters(enabled)
    guard let descriptor = SceneCatalogNativeDescriptor.parse(initial),
      let runtime = SceneCatalogNativeProgram(descriptor: descriptor, device: device) else { throw SceneCreatorFailure("Continuity fixture rejected") }
    runtime.setPlaying(true, hostTime: 0)
    _ = runtime.consume(signal(0, music: true))
    try autoreleasepool { _ = try runtime.render(target: CGRect(x:0,y:0,width:160,height:284), hostTime:0, reducedMotion:false) }
    let identity = runtime.creatorMetrics?["instance"] as? String
    let changed = parameters(program.reactivity == "music", width: 480)
    guard let transaction = runtime.prepareControlUpdate(parameters: changed) else { throw SceneCreatorFailure("Controls/resize recreate native state") }
    transaction.apply()
    try autoreleasepool { _ = try runtime.render(target: CGRect(x:0,y:0,width:240,height:284), hostTime:1.0/30, reducedMotion:false) }
    guard identity != nil, runtime.creatorMetrics?["instance"] as? String == identity,
      runtime.creatorMetrics?["updates"] as? Int == 2 else { throw SceneCreatorFailure("Native instance lost on control update") }
    transaction.rollback()
    guard runtime.prepareControlUpdate(parameters: parameters(enabled, seed: 43)) == nil else { throw SceneCreatorFailure("Changed seed did not require reset") }
    func document(_ parameters: [String: Any], reactive: Bool) -> [String: Any] {
      ["sceneId":"test","isAudioReactive":reactive,"layers":[["id":"layer", "sourceKind":"procedural", "proceduralPreset":"native_program_v1",
        "audioReactive":reactive,"proceduralParameters":parameters]]]
    }
    guard SceneCatalogControlUpdatePlan.changes(from: document(initial, reactive: enabled),
      to: document(changed, reactive: program.reactivity == "music"))?.count == 1 else { throw SceneCreatorFailure("Document update discarded stateful control transaction") }
    print("PASS continuity creator_\(program.id): resize, controls, reaction, rollback and seed reset")
  }
  static func signal(_ sequence: Int, music: Bool) -> SceneRenderSignalFrameV2 {
    let event = SceneRenderSignalEventV2(serial: Int64(sequence / 12 + 1), active: music && sequence % 12 == 0,
      timestampMicros: Int64(sequence * 33333), strength: music ? 0.8 : 0, band: .low)
    let zero = SceneRenderSignalEventV2(serial: 0, active: false, timestampMicros: 0, strength: 0, band: .none)
    return SceneRenderSignalFrameV2(sessionId: 2, sequence: Int64(sequence), audioTimestampMicros: Int64(sequence * 33333),
      available: music, fresh: true, musicActive: music, tonalAvailable: false,
      dynamics: [Float](repeating: music ? 0.8 : 0, count: 6), channels: [Float](repeating: music ? 0.8 : 0, count: 4),
      spectrumSummary: [Float](repeating: 0, count: 7), instantSpectrum: [Float](repeating: 0, count: 31),
      smoothedSpectrum: [Float](repeating: 0, count: 31), semantics: [Float](repeating: 0, count: 6),
      rhythm: [music ? 120 : 0, 0.5, 0, 0], onsets: [0,0,0,0], tonal: [0,0,0], impact: event, accent: zero, beat: event, flash: zero)
  }
  static func pixels(_ texture: MTLTexture, device: MTLDevice) throws -> [UInt8] {
    guard let queue = device.makeCommandQueue(), let command = queue.makeCommandBuffer(),
      let buffer = device.makeBuffer(length: texture.width * texture.height * 4, options: .storageModeShared),
      let blit = command.makeBlitCommandEncoder() else { throw SceneCreatorFailure("Readback unavailable") }
    blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x:0,y:0,z:0),
      sourceSize: MTLSize(width:texture.width,height:texture.height,depth:1), to: buffer, destinationOffset: 0,
      destinationBytesPerRow: texture.width*4, destinationBytesPerImage: texture.width*texture.height*4)
    blit.endEncoding(); command.commit(); command.waitUntilCompleted()
    return Array(UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: UInt8.self), count: buffer.length))
  }
  static func png(_ bytes: [UInt8], width: Int, height: Int, url: URL) throws {
    guard let provider = CGDataProvider(data: Data(bytes) as CFData),
      let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width*4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
      let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw SceneCreatorFailure("PNG encoder unavailable") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw SceneCreatorFailure("PNG write failed") }
  }
  static func main() throws {
    guard CommandLine.arguments.count == 3, let device = MTLCreateSystemDefaultDevice() else { throw SceneCreatorFailure("Metal device / catalog arguments required") }
    let catalog = CommandLine.arguments[1], output = URL(fileURLWithPath: CommandLine.arguments[2])
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    SceneCreatorCatalog.loadBundledIfNeeded(assetPath: catalog)
    let root = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: catalog))) as! [String: Any]
    for entry in root["visuals"] as! [[String: Any]] where entry["kind"] as? String == "scene" {
      let id = entry["programId"] as! String
      guard let program = SceneCreatorCatalog.program(id) else { throw SceneCreatorFailure("Native catalog rejected \(id): \(SceneCreatorCatalog.diagnostics)") }
      try continuity(program, device: device)
      func render(music: Bool, disabled: Bool = false) throws -> [UInt8] {
        let reactive = program.reactivity != "none" && !disabled
        let scene = try SceneCreatorNativeScene(program: program, options: [:], mode: nil, reactive: reactive, seed: nil, device: device)
        let allocator = SceneSurfaceNativeOutputAllocator(device: device, shaderWrite: true)
        scene.setPlaying(true, hostTime: 0)
        var last: MTLTexture?
        for i in 0...60 {
          _ = scene.consume(signal(i, music: music))
          last = try scene.render(size: CGSize(width: 320, height: 568), hostTime: Double(i)/30,
            reducedMotion: false, width: 320, height: 568, outputAllocator: allocator)
        }
        return try pixels(last!, device: device)
      }
      let neutral = try render(music: false), active = try render(music: true)
      if program.id == "composition_probe" {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
          .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
          .appendingPathComponent("studio/test/fixtures/native_composition/pixels.json")
        let samples = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as! [[Any]]
        for sample in samples {
          let offset = ((sample[1] as! Int) * 320 + (sample[0] as! Int)) * 4
          let rgba = sample[2] as! [Int]
          for channel in 0..<4 {
            let bgraChannel = channel == 0 ? 2 : channel == 2 ? 0 : channel
            guard abs(Int(active[offset + bgraChannel]) - rgba[channel]) <= 2 else {
              throw SceneCreatorFailure("Composition pixels differ at \(sample): channel \(channel)")
            }
          }
        }
        print("PASS image/sampler orientation, true group opacity, nested clips, holes, plus and screen")
      }
      try png(active, width: 320, height: 568, url: output.appendingPathComponent("\(id).png"))
      try png(neutral, width: 320, height: 568, url: output.appendingPathComponent("\(id)_neutral.png"))
      let different = zip(neutral, active).filter { abs(Int($0)-Int($1)) > 2 }.count
      if program.reactivity == "none" { guard different == 0 else { throw SceneCreatorFailure("Ambient scene reacts: \(id)") } }
      else { guard different > 16 else { throw SceneCreatorFailure("Musical scene has no visible reaction: \(id)") } }
      if program.reactivity == "optional" {
        let disabled = try render(music: true, disabled: true)
        guard zip(neutral,disabled).allSatisfy({ abs(Int($0)-Int($1)) <= 1 }) else { throw SceneCreatorFailure("Disabled reaction still changes pixels: \(id)") }
      }
      let alpha = stride(from: 3, to: active.count, by: 4).map { active[$0] }
      if program.role == "background" { guard alpha.allSatisfy({$0==255}) else { throw SceneCreatorFailure("Background is not opaque: \(id)") } }
      else { guard alpha.contains(where: {$0<16}), alpha.contains(where: {$0>16}) else { throw SceneCreatorFailure("Overlay lacks visible/translucent content: \(id)") } }
      try png(active, width: 320, height: 568, url: output.appendingPathComponent("\(id).png"))
      print("PASS authored \(id): native Metal scene, alpha and state replay")
      print("PASS behavior \(id): \(program.reactivity), identical-history musical/neutral probes")
    }
  }
}
