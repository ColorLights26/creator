import CoreFoundation
import CryptoKit
import Foundation

struct SceneRenderV2ShadowPreflightResult: Equatable {
  let semanticPlanHash: String
  let registryRevision: String
  let capabilityClass: String
  let issueCodes: [String]

  var payload: [String: Any] {
    [
      "supported": false,
      "semanticPlanHash": semanticPlanHash,
      "registryRevision": registryRevision,
      "capabilityClass": capabilityClass,
      "supportedQualityLevels": [],
      "issueCodes": issueCodes,
    ]
  }
}

/// Resource-free V2 validator used while the new native graph is in shadow.
/// It proves parser/hash parity but never claims executable support.
enum SceneRenderV2ShadowCompiler {
  private static let qualityLevels = Set([
    "best", "sustained", "minimumFunctional",
  ])
  private static let forbiddenExecutableKeys = Set([
    "code", "dart", "glsl", "metal", "shader", "shaderSource", "source",
  ])

  static func preflight(
    arguments: Any?,
    metalAvailable: Bool
  ) -> SceneRenderV2ShadowPreflightResult? {
    guard
      let arguments = arguments as? [String: Any],
      Set(arguments.keys) == Set([
        "sceneDocumentV2", "semanticPlanHash", "registryRevision",
      ]),
      let document = arguments["sceneDocumentV2"] as? [String: Any],
      let suppliedHash = arguments["semanticPlanHash"] as? String,
      isSHA256(suppliedHash),
      let suppliedRevision = arguments["registryRevision"] as? String,
      suppliedRevision == SceneRenderNodeRegistryV1Generated.revision,
      let registry = registryDefinitions()
    else {
      return nil
    }

    var issues = validateDocument(document, registry: registry)
    if semanticPlanHash(document: document) != suppliedHash {
      issues.append("semantic_plan_hash_mismatch")
    }
    if !metalAvailable {
      issues.append("graphics_api_unavailable")
    }
    if issues.isEmpty {
      // Shadow validation is not runtime certification. This issue is removed
      // only when all three native quality plans publish complete frames.
      issues.append("v2_runtime_not_installed")
    }
    return SceneRenderV2ShadowPreflightResult(
      semanticPlanHash: suppliedHash,
      registryRevision: suppliedRevision,
      capabilityClass: metalAvailable ? "ios_metal_v2_shadow" : "ios_unavailable",
      issueCodes: Array(Set(issues)).sorted()
    )
  }

  static func semanticPlanHash(document: [String: Any]) -> String? {
    guard
      let schemaVersion = document["schemaVersion"],
      let layers = document["layers"]
    else {
      return nil
    }
    var semanticDocument: [String: Any] = [
      "schemaVersion": schemaVersion,
      "layers": layers,
    ]
    if let filter = document["filterNode"] {
      semanticDocument["filterNode"] = filter
    }
    let root: [String: Any] = [
      "sceneRenderDocumentSchema": 2,
      "registryRevision": SceneRenderNodeRegistryV1Generated.revision,
      "document": semanticDocument,
    ]
    guard let data = canonicalJSONData(root) else {
      return nil
    }
    return SHA256.hash(data: data).map {
      String(format: "%02x", $0)
    }.joined()
  }

  static func qualityPlanHash(
    document: [String: Any],
    quality: String
  ) -> String? {
    guard
      qualityLevels.contains(quality),
      let rawLayers = document["layers"] as? [[String: Any]],
      let passes = plannedPasses(
        layers: rawLayers,
        hasFilter: document["filterNode"] != nil
      )
    else {
      return nil
    }
    var selectedLayers = [[String: Any]]()
    for rawLayer in rawLayers {
      var layer = rawLayer
      guard
        var node = layer["node"] as? [String: Any],
        let variants = node["qualityVariants"] as? [String: Any],
        let selected = variants[quality] as? [String: Any]
      else {
        return nil
      }
      node.removeValue(forKey: "qualityVariants")
      node["selectedQuality"] = selected
      layer["node"] = node
      selectedLayers.append(layer)
    }
    var root: [String: Any] = [
      "sceneRenderQualityPlanSchema": 1,
      "registryRevision": SceneRenderNodeRegistryV1Generated.revision,
      "quality": quality,
      "layers": selectedLayers,
      "passes": passes,
    ]
    if var filter = document["filterNode"] as? [String: Any] {
      guard
        let variants = filter["qualityVariants"] as? [String: Any],
        let selected = variants[quality] as? [String: Any]
      else {
        return nil
      }
      filter.removeValue(forKey: "qualityVariants")
      filter["selectedQuality"] = selected
      root["filterNode"] = filter
    }
    guard let data = canonicalJSONData(root) else {
      return nil
    }
    return SHA256.hash(data: data).map {
      String(format: "%02x", $0)
    }.joined()
  }

  private static func plannedPasses(
    layers: [[String: Any]],
    hasFilter: Bool
  ) -> [[String: Any]]? {
    var result = [[String: Any]]()
    var index = 0
    while index < layers.count {
      let first = layers[index]
      guard let firstID = first["id"] as? String else { return nil }
      if index + 1 < layers.count {
        let second = layers[index + 1]
        guard let secondID = second["id"] as? String else { return nil }
        if isInfernoPackedAlphaPair(first: first, second: second) {
          result.append([
            "passType": "optimizer.infernoPackedAlpha.onePass.v1",
            "layerIds": [firstID, secondID],
          ])
          index += 2
          continue
        }
      }
      result.append([
        "passType": "composite.node.v1",
        "layerIds": [firstID],
      ])
      index += 1
    }
    if hasFilter {
      result.append([
        "passType": "post.filterGrade.v1",
        "layerIds": [String](),
      ])
    }
    return result
  }

  private static func isInfernoPackedAlphaPair(
    first: [String: Any],
    second: [String: Any]
  ) -> Bool {
    guard
      let firstNode = first["node"] as? [String: Any],
      let secondNode = second["node"] as? [String: Any],
      let firstParameters = firstNode["parameters"] as? [String: Any]
    else {
      return false
    }
    return firstNode["nodeType"] as? String == "program.installed" &&
      firstParameters["programId"] as? String == "inferno_embers_v1" &&
      secondNode["nodeType"] as? String == "media.packedAlphaVideo" &&
      number(first["opacity"], equals: 1) &&
      number(second["opacity"], equals: 1) &&
      first["blendMode"] as? String == "sourceOver" &&
      second["blendMode"] as? String == "sourceOver" &&
      isIdentityTransform(first["transform"]) &&
      isIdentityTransform(second["transform"])
  }

  private static func isIdentityTransform(_ value: Any?) -> Bool {
    guard let transform = value as? [String: Any] else { return false }
    return Set(transform.keys) == Set([
      "width", "height", "scale", "rotation", "offsetX", "offsetY", "flipped",
    ]) &&
      number(transform["width"], equals: 1) &&
      number(transform["height"], equals: 1) &&
      number(transform["scale"], equals: 1) &&
      number(transform["rotation"], equals: 0) &&
      number(transform["offsetX"], equals: 0) &&
      number(transform["offsetY"], equals: 0) &&
      transform["flipped"] as? Bool == false
  }

  private static func number(_ value: Any?, equals expected: Double) -> Bool {
    guard let value = value as? NSNumber else { return false }
    return value.doubleValue.isFinite && value.doubleValue == expected
  }

  static var registryDefinitionCountForTesting: Int {
    registryDefinitions()?.count ?? 0
  }

  private static func registryDefinitions() -> [String: [String: Any]]? {
    guard
      let data = SceneRenderNodeRegistryV1Generated.canonicalJSON.data(
        using: .utf8
      ),
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      (root["schemaVersion"] as? NSNumber)?.intValue == 1,
      root["revision"] as? String == SceneRenderNodeRegistryV1Generated.revision,
      let definitions = root["definitions"] as? [[String: Any]]
    else {
      return nil
    }
    var byKey = [String: [String: Any]]()
    for definition in definitions {
      guard
        let nodeType = definition["nodeType"] as? String,
        let version = (definition["nodeVersion"] as? NSNumber)?.intValue,
        version > 0
      else {
        return nil
      }
      let key = "\(nodeType).v\(version)"
      guard byKey.updateValue(definition, forKey: key) == nil else {
        return nil
      }
    }
    return byKey
  }

  private static func validateDocument(
    _ document: [String: Any],
    registry: [String: [String: Any]]
  ) -> [String] {
    let allowedDocumentKeys = Set([
      "schemaVersion", "sceneId", "layers", "filterNode",
    ])
    guard
      Set(document.keys).isSubset(of: allowedDocumentKeys),
      (document["schemaVersion"] as? NSNumber)?.intValue == 2,
      let sceneId = document["sceneId"] as? String,
      !sceneId.isEmpty,
      let layers = document["layers"] as? [[String: Any]],
      !layers.isEmpty,
      layers.count <= 32
    else {
      return ["graph_invalid"]
    }

    var issues = [String]()
    var ids = Set<String>()
    var videoDecoders = 0
    var packedDecoders = 0
    var renderPasses = 0
    var boundedIntermediatePasses = 0
    var samplers = 0
    var memoryUnits = 0
    for layer in layers {
      guard
        let id = layer["id"] as? String,
        !id.isEmpty,
        ids.insert(id).inserted,
        let node = layer["node"] as? [String: Any]
      else {
        issues.append("layer_invalid")
        continue
      }
      issues.append(contentsOf: validateNode(node, registry: registry))
      guard
        let nodeType = node["nodeType"] as? String,
        let version = (node["nodeVersion"] as? NSNumber)?.intValue,
        let definition = registry["\(nodeType).v\(version)"],
        let cost = definition["cost"] as? [String: Any]
      else {
        continue
      }
      videoDecoders += (cost["videoDecoders"] as? NSNumber)?.intValue ?? 0
      packedDecoders +=
        (cost["packedAlphaDecoders"] as? NSNumber)?.intValue ?? 0
      renderPasses += (cost["renderPasses"] as? NSNumber)?.intValue ?? 0
      boundedIntermediatePasses += (cost["boundedIntermediatePasses"] as? NSNumber)?.intValue ?? 0
      samplers += (cost["samplers"] as? NSNumber)?.intValue ?? 0
      memoryUnits += (cost["memoryUnits"] as? NSNumber)?.intValue ?? 0
    }
    if let filter = document["filterNode"] as? [String: Any] {
      issues.append(contentsOf: validateNode(filter, registry: registry))
    } else if document.keys.contains("filterNode") {
      issues.append("filter_invalid")
    }
    if videoDecoders > 2 { issues.append("budget_video_decoders") }
    if packedDecoders > 2 { issues.append("budget_packed_alpha_decoders") }
    if renderPasses > 12 { issues.append("budget_render_passes") }
    if boundedIntermediatePasses > 192 { issues.append("budget_bounded_intermediate_passes") }
    if samplers > 16 { issues.append("budget_samplers") }
    if memoryUnits > 48 { issues.append("budget_memory") }
    if containsExecutableSource(document) {
      issues.append("remote_executable_source")
    }
    return issues
  }

  private static func validateNode(
    _ node: [String: Any],
    registry: [String: [String: Any]]
  ) -> [String] {
    let expectedKeys = Set([
      "nodeType", "nodeVersion", "parameters", "resourceSlots",
      "signalBindings", "qualityVariants", "transitionStrategy",
    ])
    guard
      Set(node.keys) == expectedKeys,
      let nodeType = node["nodeType"] as? String,
      let version = (node["nodeVersion"] as? NSNumber)?.intValue,
      let definition = registry["\(nodeType).v\(version)"],
      let parameters = node["parameters"] as? [String: Any],
      let resources = node["resourceSlots"] as? [[String: Any]],
      let signalBindings = node["signalBindings"] as? [[String: Any]],
      let variants = node["qualityVariants"] as? [String: Any],
      Set(variants.keys) == qualityLevels,
      let qualityProfile = definition["qualityProfile"] as? [String: Any],
      Set(qualityProfile.keys) == qualityLevels,
      let transition = node["transitionStrategy"] as? String
    else {
      return ["node_invalid"]
    }
    let parameterKeys = Set(definition["parameterKeys"] as? [String] ?? [])
    let requiredKeys = Set(
      definition["requiredParameterKeys"] as? [String] ?? []
    )
    let transitions = Set(
      definition["transitionStrategies"] as? [String] ?? []
    )
    let resourceKinds = Set(definition["resourceKinds"] as? [String] ?? [])
    let signalPaths = Set(definition["signalPaths"] as? [String] ?? [])
    var issues = [String]()
    if !Set(parameters.keys).isSubset(of: parameterKeys) {
      issues.append("unknown_parameter")
    }
    if !Set(parameters.keys).isSuperset(of: requiredKeys) {
      issues.append("missing_parameter")
    }
    if !transitions.contains(transition) {
      issues.append("unsupported_transition")
    }
    if
      let installed = definition["installedProgramIds"] as? [String],
      let programId = parameters["programId"] as? String,
      !installed.contains(programId)
    {
      issues.append("program_not_installed")
    }
    let backends = Set(definition["backendKeys"] as? [String] ?? [])
    if backends.isDisjoint(with: Set(["metal_ci", "metal_program"])) {
      issues.append("backend_not_installed")
    }
    var resourceSlots = Set<String>()
    var resourceIds = Set<String>()
    for resource in resources {
      let allowedKeys = Set([
        "slot", "resourceId", "kind", "path", "asset", "uri",
        "assetPackage", "sha256",
      ])
      let locations = ["path", "asset", "uri"].filter {
        resource[$0] is String
      }
      guard
        Set(resource.keys).isSubset(of: allowedKeys),
        let slot = resource["slot"] as? String,
        !slot.isEmpty,
        resourceSlots.insert(slot).inserted,
        let resourceId = resource["resourceId"] as? String,
        !resourceId.isEmpty,
        resourceIds.insert(resourceId).inserted,
        let kind = resource["kind"] as? String,
        resourceKinds.contains(kind),
        locations.count == 1,
        resource["asset"] != nil || resource["assetPackage"] == nil,
        resource["sha256"] == nil ||
          ((resource["sha256"] as? String).map(isSHA256) == true)
      else {
        issues.append("resource_invalid")
        continue
      }
    }
    var signalTargets = Set<String>()
    for binding in signalBindings {
      let allowedKeys = Set([
        "signal", "target", "scale", "bias", "minimum", "maximum",
      ])
      guard
        Set(binding.keys).isSubset(of: allowedKeys),
        let signal = binding["signal"] as? String,
        signalPaths.contains(signal),
        let target = binding["target"] as? String,
        !target.isEmpty,
        signalTargets.insert(target).inserted,
        finiteNumber(binding["scale"]),
        finiteNumber(binding["bias"]),
        binding["minimum"] == nil || finiteNumber(binding["minimum"]),
        binding["maximum"] == nil || finiteNumber(binding["maximum"])
      else {
        issues.append("signal_binding_invalid")
        continue
      }
    }
    guard
      let bestVariant = variants["best"] as? [String: Any],
      let authoredFramesPerSecond =
        (bestVariant["framesPerSecond"] as? NSNumber)?.intValue
    else {
      issues.append("quality_variant_invalid")
      return issues
    }
    for quality in qualityLevels {
      guard
        let variant = variants[quality] as? [String: Any],
        let policy = qualityProfile[quality] as? [String: Any],
        Set(policy.keys) == Set(["renderScale", "framesPerSecondCap"]),
        let expectedScale = (policy["renderScale"] as? NSNumber)?.doubleValue,
        let framesPerSecondCap =
          (policy["framesPerSecondCap"] as? NSNumber)?.intValue,
        Set(variant.keys) == Set([
          "level", "parameterOverrides", "renderScale",
          "framesPerSecond", "resourceOverrides",
        ]),
        variant["level"] as? String == quality,
        let renderScale = (variant["renderScale"] as? NSNumber)?.doubleValue,
        renderScale.isFinite,
        renderScale > 0,
        renderScale <= 1,
        renderScale == expectedScale,
        let fps = (variant["framesPerSecond"] as? NSNumber)?.intValue,
        (1...120).contains(fps),
        fps == min(authoredFramesPerSecond, framesPerSecondCap),
        let parameterOverrides = variant["parameterOverrides"] as? [String: Any],
        Set(parameterOverrides.keys).isSubset(of: parameterKeys),
        let resourceOverrides = variant["resourceOverrides"] as? [String: Any],
        resourceOverrides.allSatisfy({ slot, resourceId in
          resourceSlots.contains(slot) &&
            (resourceId as? String).map(resourceIds.contains) == true
        })
      else {
        issues.append("quality_variant_invalid")
        continue
      }
    }
    return issues
  }

  private static func containsExecutableSource(_ value: Any) -> Bool {
    if let dictionary = value as? [String: Any] {
      return dictionary.contains { key, child in
        forbiddenExecutableKeys.contains(key) || containsExecutableSource(child)
      }
    }
    if let list = value as? [Any] {
      return list.contains(where: containsExecutableSource)
    }
    return false
  }

  private static func canonicalJSONData(_ value: Any) -> Data? {
    canonicalJSONString(value)?.data(using: .utf8)
  }

  private static func canonicalJSONString(_ value: Any) -> String? {
    if value is NSNull { return "null" }
    if let string = value as? String {
      guard
        let data = try? JSONSerialization.data(
          withJSONObject: [string],
          options: [.withoutEscapingSlashes]
        ),
        let encoded = String(data: data, encoding: .utf8),
        encoded.count >= 2
      else {
        return nil
      }
      return String(encoded.dropFirst().dropLast())
    }
    if let dictionary = value as? [String: Any] {
      var children = [String]()
      children.reserveCapacity(dictionary.count)
      for key in dictionary.keys.sorted() {
        guard
          let encodedKey = canonicalJSONString(key),
          let child = dictionary[key],
          let encodedChild = canonicalJSONString(child)
        else {
          return nil
        }
        children.append("\(encodedKey):\(encodedChild)")
      }
      return "{\(children.joined(separator: ","))}"
    }
    if let list = value as? [Any] {
      var children = [String]()
      children.reserveCapacity(list.count)
      for child in list {
        guard let encoded = canonicalJSONString(child) else { return nil }
        children.append(encoded)
      }
      return "[\(children.joined(separator: ","))]"
    }
    if let number = value as? NSNumber {
      if CFGetTypeID(number) == CFBooleanGetTypeID() {
        return number.boolValue ? "true" : "false"
      }
      return canonicalNumber(number.doubleValue)
    }
    return nil
  }

  private static func canonicalNumber(_ value: Double) -> String? {
    guard value.isFinite else { return nil }
    if value == 0 { return "0" }
    if
      value >= -9_007_199_254_740_991,
      value <= 9_007_199_254_740_991,
      value.rounded() == value
    {
      return String(Int64(value))
    }
    let raw = String(value).lowercased()
    let magnitude = abs(value)
    if magnitude < 0.000001 || magnitude >= 1_000_000_000_000_000_000_000 {
      return normalizedScientificNumber(raw)
    }
    let expanded = raw.contains("e") ? expandedScientificNumber(raw) : raw
    guard let expanded else { return nil }
    return expanded.contains(".") ? expanded : "\(expanded).0"
  }

  private static func normalizedScientificNumber(_ value: String) -> String? {
    let components = value.split(separator: "e", omittingEmptySubsequences: false)
    guard
      components.count == 2,
      let exponent = Int(components[1])
    else {
      return nil
    }
    let sign = exponent >= 0 ? "+" : ""
    return "\(components[0])e\(sign)\(exponent)"
  }

  private static func expandedScientificNumber(_ value: String) -> String? {
    let components = value.split(separator: "e", omittingEmptySubsequences: false)
    guard
      components.count == 2,
      let exponent = Int(components[1])
    else {
      return nil
    }
    var coefficient = String(components[0])
    let negative = coefficient.hasPrefix("-")
    if negative { coefficient.removeFirst() }
    let coefficientParts = coefficient.split(
      separator: ".",
      omittingEmptySubsequences: false
    )
    guard coefficientParts.count <= 2 else { return nil }
    let integerDigits = coefficientParts[0].count
    let digits = coefficientParts.joined()
    let decimalIndex = integerDigits + exponent
    let expanded: String
    if decimalIndex <= 0 {
      expanded = "0." + String(repeating: "0", count: -decimalIndex) + digits
    } else if decimalIndex >= digits.count {
      expanded = digits + String(repeating: "0", count: decimalIndex - digits.count)
    } else {
      let split = digits.index(digits.startIndex, offsetBy: decimalIndex)
      expanded = String(digits[..<split]) + "." + String(digits[split...])
    }
    return negative ? "-\(expanded)" : expanded
  }

  private static func isSHA256(_ value: String) -> Bool {
    value.count == 64 && value.allSatisfy {
      ("0"..."9").contains(String($0)) || ("a"..."f").contains(String($0))
    }
  }

  private static func finiteNumber(_ value: Any?) -> Bool {
    guard let number = value as? NSNumber else { return false }
    return number.doubleValue.isFinite
  }
}
