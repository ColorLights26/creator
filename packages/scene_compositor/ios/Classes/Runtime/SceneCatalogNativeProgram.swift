import Foundation
import CoreGraphics
import CoreImage
import Metal

/// The existing scene owner supplies time, signals and output lifetime. These
/// component states do not start a second scene, audio subscription or timer.
protocol SceneCatalogShaderState: AnyObject {
  func consume(_ frame: SceneRenderSignalFrameV2) -> Bool
  func setPlaying(_ playing: Bool, hostTime: Double)
  func uniforms(size: CGSize, hostTime: Double, reducedMotion: Bool) -> [Float]
  func inheritAnimation(from previous: SceneCatalogShaderState) -> Bool
}

extension SceneCatalogFamilyShaderState: SceneCatalogShaderState {
  func inheritAnimation(from previous: SceneCatalogShaderState) -> Bool {
    guard let previous = previous as? SceneCatalogFamilyShaderState else { return false }
    inheritAnimation(from: previous)
    return true
  }
}
extension SceneCatalogIndividualShaderState: SceneCatalogShaderState {
  func inheritAnimation(from previous: SceneCatalogShaderState) -> Bool {
    guard let previous = previous as? SceneCatalogIndividualShaderState else { return false }
    inheritAnimation(from: previous)
    return true
  }
}

/// All layers prepare before any mutation. A failed first presentation restores
/// the previous controls without releasing decoders or restarting their clocks.
struct SceneCatalogControlUpdate {
  let apply: () -> Void
  let rollback: () -> Void
}

enum SceneCatalogControlUpdatePlan {
  struct PresentationChanges {
    let order: [Int]
    let controls: [(Int, [String: Any])]
  }

  /// A layer's placement is not its media identity. Match by stable layer ID,
  /// then use the existing strict source/control comparison in original order.
  static func presentationChanges(from current: [String: Any], to next: [String: Any]) -> PresentationChanges? {
    guard let old = current["layers"] as? [[String: Any]],
      let proposed = next["layers"] as? [[String: Any]], old.count == proposed.count,
      !old.isEmpty else { return nil }
    var indices = [String: Int]()
    for (index, layer) in old.enumerated() {
      guard let id = layer["id"] as? String, indices.updateValue(index, forKey: id) == nil else { return nil }
    }
    var order = [Int](), normalized = old, seen = Set<Int>()
    for (position, layer) in proposed.enumerated() {
      guard let id = layer["id"] as? String, let index = indices[id], seen.insert(index).inserted,
        validPresentation(layer), layer["role"] as? String != "background" || position == 0
      else { return nil }
      var value = layer
      value["opacity"] = old[index]["opacity"]
      value["transform"] = old[index]["transform"]
      normalized[index] = value
      order.append(index)
    }
    var normalizedDocument = next
    normalizedDocument["layers"] = normalized
    guard let controls = changes(from: current, to: normalizedDocument) else { return nil }
    return PresentationChanges(order: order, controls: controls)
  }

  static func validPresentation(_ layer: [String: Any]) -> Bool {
    func number(_ value: Any?, _ low: Double, _ high: Double) -> Bool {
      guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
        value.doubleValue.isFinite else { return false }
      return (low...high).contains(value.doubleValue)
    }
    guard number(layer["opacity"], 0, 1), let transform = layer["transform"] as? [String: Any],
      Set(transform.keys) == ["width", "height", "offsetX", "offsetY", "scale", "rotation", "flipped"],
      transform["flipped"] is Bool else { return false }
    return number(transform["width"], 0.01, 4) && number(transform["height"], 0.01, 4) &&
      number(transform["offsetX"], -4, 4) && number(transform["offsetY"], -4, 4) &&
      number(transform["scale"], 0.05, 10) && number(transform["rotation"], -Double.pi * 8, Double.pi * 8)
  }

  /// Controls and final grade can change without recreating layers/decoders.
  /// Structural changes keep the existing full document transaction.
  static func changes(from current: [String: Any], to next: [String: Any]) -> [(Int, [String: Any])]? {
    guard let previousLayers = current["layers"] as? [[String: Any]],
      let nextLayers = next["layers"] as? [[String: Any]],
      previousLayers.count == nextLayers.count else { return nil }
    var previousHeader = current, nextHeader = next
    previousHeader.removeValue(forKey: "layers")
    nextHeader.removeValue(forKey: "layers")
    previousHeader.removeValue(forKey: "filter")
    nextHeader.removeValue(forKey: "filter")
    guard equal(previousHeader, nextHeader) else { return nil }
    var changes = [(Int, [String: Any])]()
    for index in previousLayers.indices {
      let previous = previousLayers[index], proposed = nextLayers[index]
      if equal(previous, proposed) { continue }
      guard let previousParameters = previous["proceduralParameters"] as? [String: Any],
        let parameters = proposed["proceduralParameters"] as? [String: Any]
      else { return nil }
      if previous["sourceKind"] as? String == "realtimeRenderer" {
        guard Set(previousParameters.keys) == ["visualControls"],
          Set(parameters.keys) == ["visualControls"],
          previousParameters["visualControls"] is [String: Any],
          parameters["visualControls"] is [String: Any] else { return nil }
      } else {
        guard previous["sourceKind"] as? String == "procedural",
          previous["proceduralPreset"] as? String == "native_program_v1",
          let identity = controlIdentity(previousParameters),
          identity == controlIdentity(parameters) else { return nil }
      }
      var previousStructure = previous, proposedStructure = proposed
      previousStructure.removeValue(forKey: "proceduralParameters")
      proposedStructure.removeValue(forKey: "proceduralParameters")
      guard equal(previousStructure, proposedStructure) else { return nil }
      changes.append((index, parameters))
    }
    return changes
  }

  static func controlIdentity(_ input: [String: Any]) -> Data? {
    var input = input
    guard var document = input["document"] as? [String: Any],
      var layers = document["layers"] as? [[String: Any]], layers.count == 1,
      var node = layers[0]["node"] as? [String: Any],
      var parameters = node["parameters"] as? [String: Any] else { return nil }
    parameters.removeValue(forKey: "mode")
    parameters.removeValue(forKey: "options")
    node["parameters"] = parameters
    layers[0]["node"] = node
    document["layers"] = layers
    input["document"] = document
    guard JSONSerialization.isValidJSONObject(input) else { return nil }
    return try? JSONSerialization.data(withJSONObject: input, options: .sortedKeys)
  }

  private static func equal(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
    guard JSONSerialization.isValidJSONObject(lhs), JSONSerialization.isValidJSONObject(rhs),
      let left = try? JSONSerialization.data(withJSONObject: lhs, options: .sortedKeys),
      let right = try? JSONSerialization.data(withJSONObject: rhs, options: .sortedKeys)
    else { return false }
    return left == right
  }
}

struct SceneCatalogNativeDescriptor {
  let program: String
  let options: [String: Any]
  let mode: String?
  let logicalSize: CGSize
  let framesPerSecond: Int
  let audioReactive: Bool
  let seed: UInt32?
  let controlIdentity: Data

  /// Only a bundled, versioned program is executable. The document cannot supply
  /// shader source, extra resources, a different cadence or altered quality.
  static func parse(_ input: [String: Any]) -> Self? {
    guard Set(input.keys) == Set([
      "document", "resolvedResourcePaths", "logicalWidth", "logicalHeight",
    ]), let width = number(input["logicalWidth"]),
      let height = number(input["logicalHeight"]),
      width > 0, height > 0, width <= 8192, height <= 8192,
      (input["resolvedResourcePaths"] as? [String: Any])?.isEmpty == true,
      let document = input["document"] as? [String: Any],
      Set(document.keys) == Set(["schemaVersion", "sceneId", "layers"]),
      number(document["schemaVersion"]) == 2,
      validToken(document["sceneId"]),
      let layers = document["layers"] as? [[String: Any]], layers.count == 1,
      let layer = layers.first, validToken(layer["id"]),
      number(layer["opacity"]) == 1, number(layer["playbackRate"]) == 1,
      layer["blendMode"] as? String == "sourceOver",
      layer["alphaMode"] as? String == "normal",
      layer["fallbackPolicy"] as? String == "continuousCompatibility",
      let transform = layer["transform"] as? [String: Any],
      Set(transform.keys) == Set([
        "width", "height", "offsetX", "offsetY", "scale", "rotation", "flipped",
      ]), number(transform["width"]) == 1, number(transform["height"]) == 1,
      number(transform["offsetX"]) == 0, number(transform["offsetY"]) == 0,
      number(transform["scale"]) == 1, number(transform["rotation"]) == 0,
      transform["flipped"] as? Bool == false,
      let node = layer["node"] as? [String: Any],
      Set(node.keys) == Set([
        "nodeType", "nodeVersion", "parameters", "resourceSlots",
        "signalBindings", "qualityVariants", "transitionStrategy",
      ]), let nodeType = node["nodeType"] as? String,
      ["effect.catalogProgram", "effect.catalogVectorProgram"].contains(nodeType),
      number(node["nodeVersion"]) == 1,
      node["transitionStrategy"] as? String == "stateReplay",
      (node["resourceSlots"] as? [Any])?.isEmpty == true,
      let parameters = node["parameters"] as? [String: Any],
      Set(parameters.keys).isSubset(of: Set([
        "programId", "audioReactive", "mode", "options", "effect", "seed",
      ])), let program = parameters["programId"] as? String,
      (SceneCatalogShaderSources.programs[program] != nil || SceneCreatorCatalog.program(program) != nil ||
        ["magic_clouds", "neon_club", "aurora_spectrum", "liquid_lava_lamp", "blue_sky"].contains(program)),
      ["neon_club", "aurora_spectrum", "liquid_lava_lamp", "blue_sky"].contains(program) == (nodeType == "effect.catalogVectorProgram"),
      layer["frameRateBinding"] as? String == (program == "blue_sky" ? "staticContent" : "preferred"),
      let reactive = parameters["audioReactive"] as? Bool,
      parameters["mode"] == nil || parameters["mode"] is String,
      parameters["effect"] == nil || parameters["effect"] is String,
      let options = parameters["options"] as? [String: Any] ??
        (parameters["options"] == nil ? [:] : nil),
      options.count <= 64, options.allSatisfy({ key, value in
        guard !key.isEmpty, key.count <= 128 else { return false }
        if let value = value as? String { return value.count <= 256 }
        if value is Bool { return true }
        return number(value) != nil
      }), let bindings = node["signalBindings"] as? [[String: Any]],
      validBindings(bindings, reactive: reactive),
      number(layer["preferredFramesPerSecond"]) == Double(cadence(for: program)),
      validVariants(node["qualityVariants"], cadence: cadence(for: program))
    else { return nil }
    let transparent = SceneCreatorCatalog.program(program)?.role == "overlay" ||
      ["spectral_haze", "prismatic_lens", "magic_clouds"].contains(program)
    guard layer["role"] as? String == (transparent ? "overlay" : "background")
    else { return nil }
    // Validate the installed component's controls during preflight as well as
    // construction. A generic scalar map must not silently discard new options.
    let mode = parameters["mode"] as? String
    let seed: UInt32?
    if let raw = parameters["seed"] {
      guard SceneCreatorCatalog.program(program) != nil, let value = number(raw),
        value.rounded() == value, (0...Double(UInt32.max)).contains(value) else { return nil }
      seed = UInt32(value)
    } else { seed = nil }
    if let creator = SceneCreatorCatalog.program(program) {
      guard creator.allows(reactive: reactive),
        SceneCreatorShaderState(program: program, options: options, mode: mode, reactive: reactive, seed: seed) != nil
      else { return nil }
    } else if program == "magic_clouds" {
      guard options.isEmpty, !reactive else { return nil }
    } else if program == "neon_club" {
      guard SceneCatalogNeonClubState(options: options, mode: mode) != nil else { return nil }
    } else if program == "aurora_spectrum" {
      guard reactive, SceneCatalogAuroraState(options: options, mode: mode) != nil else { return nil }
    } else if program == "liquid_lava_lamp" {
      guard reactive, SceneCatalogLiquidLavaState(options: options, mode: mode) != nil else { return nil }
    } else if program == "blue_sky" {
      guard !reactive, SceneCatalogBlueSkyControls(options: options, mode: mode) != nil else { return nil }
    } else {
      guard SceneCatalogFamilyShaderState(program: program, options: options, mode: mode) != nil ||
        SceneCatalogIndividualShaderState(program: program, options: options, mode: mode) != nil
      else { return nil }
    }
    guard let identity = SceneCatalogControlUpdatePlan.controlIdentity(input) else { return nil }
    return Self(program: program, options: options, mode: parameters["mode"] as? String,
      logicalSize: CGSize(width: width, height: height), framesPerSecond: cadence(for: program),
      audioReactive: reactive, seed: seed, controlIdentity: identity)
  }

  private static func cadence(for program: String) -> Int {
    if let creator = SceneCreatorCatalog.program(program) { return creator.framesPerSecond }
    switch program {
    case "blue_sky": return 1
    case "magic_clouds": return 20
    case "chladni_resonance", "prismatic_tides", "event_horizon", "chromatic_silk",
         "luminous_matter", "spectral_haze", "prismatic_lens": return 30
    default: return 60
    }
  }

  private static func number(_ value: Any?) -> Double? {
    guard let value = value as? NSNumber,
      CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite
    else { return nil }
    return value.doubleValue
  }

  private static func validToken(_ value: Any?) -> Bool {
    guard let value = value as? String, !value.isEmpty, value.count <= 200 else { return false }
    return value.range(of: "^[A-Za-z0-9_.:-]+$", options: .regularExpression) != nil
  }

  private static func validBindings(_ bindings: [[String: Any]], reactive: Bool) -> Bool {
    if !reactive { return bindings.isEmpty }
    guard bindings.count == 1, let binding = bindings.first else { return false }
    return Set(binding.keys) == Set(["signal", "target", "scale", "bias"]) &&
      binding["signal"] as? String == "frame.v2" &&
      binding["target"] as? String == "runtime.signalFrame" &&
      number(binding["scale"]) == 1 && number(binding["bias"]) == 0
  }

  private static func validVariants(_ value: Any?, cadence: Int) -> Bool {
    let levels = ["best", "sustained", "minimumFunctional"]
    guard let variants = value as? [String: [String: Any]],
      Set(variants.keys) == Set(levels) else { return false }
    return levels.allSatisfy { level in
      guard let variant = variants[level] else { return false }
      return Set(variant.keys) == Set([
        "level", "parameterOverrides", "renderScale", "framesPerSecond", "resourceOverrides",
      ]) && variant["level"] as? String == level &&
        (variant["parameterOverrides"] as? [String: Any])?.isEmpty == true &&
        (variant["resourceOverrides"] as? [String: Any])?.isEmpty == true &&
        number(variant["renderScale"]) == 1 &&
        number(variant["framesPerSecond"]) == Double(cadence)
    }
  }
}

@available(iOS 15.0, *)
final class SceneCatalogNativeProgram {
  private enum Source {
    case shader(SceneCatalogShaderState, SceneCatalogShaderRenderer)
    case clouds(SceneCatalogCloudRenderer)
    case vector(SceneCatalogNeonClubState, SceneCatalogNeonClubRenderer)
    case aurora(SceneCatalogAuroraState, SceneCatalogAuroraRenderer)
    case lava(SceneCatalogLiquidLavaState, SceneCatalogLiquidLavaRenderer)
    case sky(SceneCatalogBlueSkyControls, SceneCatalogBlueSkyRenderer)
  }
  private var descriptor: SceneCatalogNativeDescriptor
  private var source: Source
  private let outputAllocator: SceneSurfaceNativeOutputAllocator
  private static let colorSpace = CGColorSpaceCreateDeviceRGB()
  private var cloudElapsed = 0.0
  private var cloudHostTime: Double?
  private var cloudPlaying = false

  init?(descriptor: SceneCatalogNativeDescriptor, device: MTLDevice) {
    self.descriptor = descriptor
    if descriptor.program == "magic_clouds" {
      guard let renderer = try? SceneCatalogCloudRenderer(device: device) else { return nil }
      source = .clouds(renderer)
    } else if descriptor.program == "neon_club" {
      guard let state = SceneCatalogNeonClubState(options: descriptor.options, mode: descriptor.mode),
        let renderer = try? SceneCatalogNeonClubRenderer(device: device) else { return nil }
      source = .vector(state, renderer)
    } else if descriptor.program == "aurora_spectrum" {
      guard let state = SceneCatalogAuroraState(options: descriptor.options, mode: descriptor.mode),
        let renderer = try? SceneCatalogAuroraRenderer(device: device) else { return nil }
      source = .aurora(state, renderer)
    } else if descriptor.program == "liquid_lava_lamp" {
      guard let state = SceneCatalogLiquidLavaState(options: descriptor.options, mode: descriptor.mode),
        let renderer = try? SceneCatalogLiquidLavaRenderer(device: device) else { return nil }
      source = .lava(state, renderer)
    } else if descriptor.program == "blue_sky" {
      guard let controls = SceneCatalogBlueSkyControls(options: descriptor.options, mode: descriptor.mode),
        let renderer = try? SceneCatalogBlueSkyRenderer(device: device) else { return nil }
      source = .sky(controls, renderer)
    } else {
      let state: SceneCatalogShaderState?
      if let creator = SceneCreatorShaderState(program: descriptor.program, options: descriptor.options,
        mode: descriptor.mode, reactive: descriptor.audioReactive, seed: descriptor.seed) { state = creator }
      else if let family = SceneCatalogFamilyShaderState(program: descriptor.program,
        options: descriptor.options, mode: descriptor.mode) { state = family }
      else { state = SceneCatalogIndividualShaderState(program: descriptor.program,
        options: descriptor.options, mode: descriptor.mode) }
      guard let state, let renderer = try? SceneCatalogShaderRenderer(device: device)
      else { return nil }
      do { try renderer.prepare(program: descriptor.program) }
      catch {
        SceneCreatorCatalog.preparationFailed(program: descriptor.program, error: error)
        return nil
      }
      source = .shader(state, renderer)
    }
    outputAllocator = SceneSurfaceNativeOutputAllocator(device: device)
  }

  var preferredFramesPerSecond: Int { descriptor.framesPerSecond }
  var needsContinuousRendering: Bool { descriptor.program != "blue_sky" }

  func prepareControlUpdate(parameters: [String: Any]) -> SceneCatalogControlUpdate? {
    guard let next = SceneCatalogNativeDescriptor.parse(parameters),
      next.controlIdentity == descriptor.controlIdentity,
      next.program == descriptor.program, next.logicalSize == descriptor.logicalSize,
      next.framesPerSecond == descriptor.framesPerSecond else { return nil }
    let replacement: Source
    switch source {
    case .shader(let current, let renderer):
      let state: SceneCatalogShaderState?
      if let creator = SceneCreatorShaderState(program: next.program, options: next.options,
        mode: next.mode, reactive: next.audioReactive, seed: next.seed) {
        state = creator
      } else if let family = SceneCatalogFamilyShaderState(program: next.program, options: next.options, mode: next.mode) {
        state = family
      } else {
        state = SceneCatalogIndividualShaderState(program: next.program, options: next.options, mode: next.mode)
      }
      guard let state, state.inheritAnimation(from: current) else { return nil }
      replacement = .shader(state, renderer)
    case .clouds:
      replacement = source
    case .vector(let current, let renderer):
      guard let state = SceneCatalogNeonClubState(options: next.options, mode: next.mode) else { return nil }
      state.inheritAnimation(from: current)
      replacement = .vector(state, renderer)
    case .aurora(let current, let renderer):
      guard let state = SceneCatalogAuroraState(options: next.options, mode: next.mode) else { return nil }
      state.inheritAnimation(from: current)
      replacement = .aurora(state, renderer)
    case .lava(let current, let renderer):
      guard let state = SceneCatalogLiquidLavaState(options: next.options, mode: next.mode) else { return nil }
      state.inheritAnimation(from: current)
      replacement = .lava(state, renderer)
    case .sky(_, let renderer):
      guard let controls = SceneCatalogBlueSkyControls(options: next.options, mode: next.mode) else { return nil }
      replacement = .sky(controls, renderer)
    }
    let previousDescriptor = descriptor
    let previousSource = source
    return SceneCatalogControlUpdate(
      apply: { [weak self] in self?.descriptor = next; self?.source = replacement },
      rollback: { [weak self] in
        self?.descriptor = previousDescriptor; self?.source = previousSource
      })
  }
  func consume(_ frame: SceneRenderSignalFrameV2) -> Bool {
    if case .shader(let state, _) = source { return state.consume(frame) }
    if case .vector(let state, _) = source { return state.consume(frame) }
    if case .aurora(let state, _) = source { return state.consume(frame) }
    if case .lava(let state, _) = source { return state.consume(frame) }
    return false
  }
  func setPlaying(_ playing: Bool, hostTime: Double) {
    switch source {
    case .shader(let state, _): state.setPlaying(playing, hostTime: hostTime)
    case .vector(let state, _): state.setPlaying(playing, hostTime: hostTime)
    case .aurora(let state, _): state.setPlaying(playing, hostTime: hostTime)
    case .lava(let state, _): state.setPlaying(playing, hostTime: hostTime)
    case .sky: break
    case .clouds:
      advanceClouds(hostTime: hostTime)
      cloudPlaying = playing
      cloudHostTime = hostTime
    }
  }

  func render(target: CGRect, hostTime: Double, reducedMotion: Bool) throws -> CIImage {
    let texture: MTLTexture
    switch source {
    case .shader(let state, let renderer):
      let values = state.uniforms(size: descriptor.logicalSize, hostTime: hostTime,
        reducedMotion: reducedMotion)
      texture = try renderer.render(program: descriptor.program, uniforms: values,
        width: Int(target.width), height: Int(target.height), outputAllocator: outputAllocator)
    case .clouds(let renderer):
      advanceClouds(hostTime: hostTime)
      texture = try renderer.render(elapsed: cloudElapsed, width: Int(target.width),
        height: Int(target.height), outputAllocator: outputAllocator)
    case .vector(let state, let renderer):
      texture = try renderer.render(frame: state.frame(size: descriptor.logicalSize, hostTime: hostTime),
        width: Int(target.width), height: Int(target.height), outputAllocator: outputAllocator)
    case .aurora(let state, let renderer):
      texture = try renderer.render(frame: state.frame(size: descriptor.logicalSize, hostTime: hostTime),
        width: Int(target.width), height: Int(target.height), outputAllocator: outputAllocator)
    case .lava(let state, let renderer):
      texture = try renderer.render(frame: state.frame(size: descriptor.logicalSize, hostTime: hostTime),
        width: Int(target.width), height: Int(target.height), outputAllocator: outputAllocator)
    case .sky(let controls, let renderer):
      texture = try renderer.render(controls: controls, seed: 1, logicalSize: descriptor.logicalSize,
        width: Int(target.width), height: Int(target.height), outputAllocator: outputAllocator)
    }
    guard let image = CIImage(mtlTexture: texture, options: [.colorSpace: Self.colorSpace])
    else { throw RenderError.invalidImage }
    return image.transformed(by: CGAffineTransform(translationX: target.minX, y: target.maxY)
      .scaledBy(x: 1, y: -1)).cropped(to: target)
  }

  private func advanceClouds(hostTime: Double) {
    guard hostTime.isFinite else { return }
    if cloudPlaying, let previous = cloudHostTime {
      cloudElapsed += max(0, hostTime - previous)
    }
    cloudHostTime = hostTime
  }

  private enum RenderError: Error { case invalidImage }
}
