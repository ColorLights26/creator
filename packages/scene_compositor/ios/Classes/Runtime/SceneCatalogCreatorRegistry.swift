import Foundation
import Metal
import CryptoKit
#if os(iOS) && !canImport(scene_program_native)
#error("Creator requires the scene_program_native pod. Resolve iOS dependencies before building.")
#endif
#if canImport(scene_program_native)
import scene_program_native
#endif

/// Creator programs are installed with the application. Scene documents can
/// select their immutable ID but cannot supply or replace executable source.
enum SceneCreatorCatalog {
  struct Program {
    let id: String
    let role: String
    let reactivity: String
    let framesPerSecond: Int
    let seed: UInt32
    let colors: [Float]
    let controls: [String: Float]
    let shader: SceneCatalogShaderDefinition?
    var nativeBuild: [String: Any] = [:]
    var images: [String: String] = [:]
    var isNative: Bool { !nativeBuild.isEmpty }

    func allows(reactive: Bool) -> Bool {
      reactivity == "optional" || (reactivity == "music") == reactive
    }
  }

  private static let lock = NSLock()
  private static var loaded = false
  private static var programs = [String: Program]()
  private static var loadError: String?
  private(set) static var assetRoot: URL?
  private static var preparationErrors = [String: String]()
  private static let maximumCatalogBytes = 4 * 1024 * 1024
  static let controlRanges: [String: ClosedRange<Float>] = [
    "intensity": 0...2, "speed": 0...2, "detail": 0.25...2, "glow": 0...2,
  ]

  static func program(_ id: String) -> Program? {
    lock.lock()
    defer { lock.unlock() }
    return programs[id]
  }

  static var diagnostics: [String: Any] {
    lock.lock()
    defer { lock.unlock() }
    var result: [String: Any] = ["loaded": loaded, "programIds": programs.keys.sorted(),
      "preparationErrors": preparationErrors]
    if let loadError { result["catalogError"] = loadError }
    return result
  }

  static func preparationFailed(program: String, error: Error) {
    lock.lock()
    defer { lock.unlock() }
    guard programs[program] != nil else { return }
    let message = String(error.localizedDescription.prefix(8192))
    guard preparationErrors[program] != message else { return }
    preparationErrors[program] = message
    NSLog("[SceneCreatorCatalog] program=%@ shader_rejected: %@", program, error.localizedDescription)
  }

  static func loadBundledIfNeeded(assetPath: String?) {
    lock.lock()
    defer { lock.unlock() }
    guard !loaded else { return }
    loaded = true
    guard let assetPath else { return }
    do {
      let size = try FileManager.default.attributesOfItem(atPath: assetPath)[.size] as? NSNumber
      guard let size, size.intValue > 0, size.intValue <= maximumCatalogBytes else {
        throw CatalogError("catalog_size_invalid")
      }
      assetRoot = URL(fileURLWithPath: assetPath).deletingLastPathComponent().deletingLastPathComponent()
      programs = try decode(Data(contentsOf: URL(fileURLWithPath: assetPath)))
    } catch {
      // An invalid package is rejected as a whole, never partly installed.
      loadError = String(error.localizedDescription.prefix(8192))
      NSLog("[SceneCreatorCatalog] bundled_catalog_rejected: %@", error.localizedDescription)
    }
  }

  static func decode(_ data: Data) throws -> [String: Program] {
    guard data.count <= maximumCatalogBytes,
      let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      Set(root.keys) == ["schemaVersion", "visuals"], number(root["schemaVersion"]) == 1,
      let values = root["visuals"] as? [[String: Any]], values.count <= 64
    else { throw CatalogError("catalog_header_invalid") }
    var result = [String: Program]()
    var ids = Set<String>()
    for value in values {
      let native = value["kind"] as? String == "scene"
      let baseKeys: Set<String> = ["id", "name", "programId", "role", "reactivity",
        "framesPerSecond", "seed", "colors", "controls", "shaderSource"]
      guard Set(value.keys) == (native ? baseKeys.union(["kind", "nativeSource", "shaderSources", "images", "nativeBuild"]) : baseKeys),
        let id = value["id"] as? String, id.range(of: "^[a-z][a-z0-9_]{0,63}$", options: .regularExpression) != nil,
        ids.insert(id).inserted,
        let name = value["name"] as? String, !name.isEmpty, name.count <= 100,
        let programID = value["programId"] as? String, programID == "creator_" + id,
        SceneCatalogShaderSources.programs[programID] == nil,
        let role = value["role"] as? String, ["background", "overlay"].contains(role),
        let reactivity = value["reactivity"] as? String, ["none", "music", "optional"].contains(reactivity),
        let fps = number(value["framesPerSecond"]), [30.0, 60.0].contains(fps),
        let seed = number(value["seed"]), seed.rounded() == seed, (0...Double(UInt32.max)).contains(seed),
        let colors = value["colors"] as? [Any], colors.count == 4,
        let controls = value["controls"] as? [String: Any], Set(controls.keys) == Set(controlRanges.keys),
        let source = value["shaderSource"] as? String,
        native ? source.isEmpty : (!source.isEmpty && source.utf8.count <= 65_536 && source.contains("paintVisual") && !source.contains("#") && !source.contains("[["))
      else { throw CatalogError("catalog_program_invalid") }
      var parsedControls = [String: Float]()
      for (key, range) in controlRanges {
        guard let value = number(controls[key]), range.contains(Float(value)) else {
          throw CatalogError("catalog_control_invalid: \(key)")
        }
        parsedControls[key] = Float(value)
      }
      var rgba = [Float]()
      for color in colors {
        guard let raw = number(color), raw.rounded() == raw, (0...Double(UInt32.max)).contains(raw)
        else { throw CatalogError("catalog_color_invalid") }
        let argb = UInt32(raw)
        rgba += [Float((argb >> 16) & 255), Float((argb >> 8) & 255), Float(argb & 255), Float(argb >> 24)].map { $0 / 255 }
      }
      if native {
        guard let build = value["nativeBuild"] as? [String: Any],
          number(build["abi"]) == 1, let hash = build["hash"] as? String, hash.count == 64,
          let images = value["images"] as? [String: String], images.count <= 16,
          let materials = build["materials"] as? [String: Any], materials.count <= 16
        else { throw CatalogError("native_program_manifest_invalid") }
        for path in images.values {
          guard path.range(of: "^assets/images/[a-zA-Z0-9_-]+\\.(png|jpg|jpeg|webp)$", options: .regularExpression) != nil
          else { throw CatalogError("native_image_path_invalid") }
        }
        #if canImport(scene_program_native)
        guard cp_abi_version() == 1, let compiled = programID.withCString({ cp_program_hash($0) }),
          String(cString: compiled) == hash else { throw CatalogError("native_program_build_mismatch: \(programID)") }
        #else
        throw CatalogError("native_program_runtime_not_linked")
        #endif
        result[programID] = Program(id: id, role: role, reactivity: reactivity,
          framesPerSecond: Int(fps), seed: UInt32(seed), colors: rgba, controls: parsedControls,
          shader: nil, nativeBuild: build, images: images)
        continue
      }
      let metalSource = shaderHeader + "\n" + source + "\n" + shaderFooter
      func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
      }
      let shader = SceneCatalogShaderDefinition(program: programID,
        sourceSHA256: hash(source), metalSHA256: hash(metalSource),
        entryPoint: "creatorFragment", floatCount: 32, uniforms: [], metalSource: metalSource)
      result[programID] = Program(id: id, role: role, reactivity: reactivity,
        framesPerSecond: Int(fps), seed: UInt32(seed), colors: rgba, controls: parsedControls, shader: shader)
    }
    return result
  }

  static func number(_ value: Any?) -> Double? {
    guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
      value.doubleValue.isFinite else { return nil }
    return value.doubleValue
  }

  struct CatalogError: LocalizedError {
    let code: String
    init(_ code: String) { self.code = code }
    var errorDescription: String? { code }
  }

  static let shaderHeader = """
  #include <metal_stdlib>
  using namespace metal;
  typedef float2 vec2;
  typedef float3 vec3;
  typedef float4 vec4;
  typedef float2x2 mat2;
  typedef float3x3 mat3;
  typedef float4x4 mat4;
  float mod(float x, float y) { return x - y * floor(x / y); }
  vec2 mod(vec2 x, vec2 y) { return x - y * floor(x / y); }
  vec3 mod(vec3 x, vec3 y) { return x - y * floor(x / y); }
  vec4 mod(vec4 x, vec4 y) { return x - y * floor(x / y); }
  vec2 mod(vec2 x, float y) { return mod(x, vec2(y)); }
  vec3 mod(vec3 x, float y) { return mod(x, vec3(y)); }
  vec4 mod(vec4 x, float y) { return mod(x, vec4(y)); }
  struct CreatorUniforms {
    float2 size; float time; uint seed;
    float energy; float bass; float body; float spark;
    float flow; float pulse; float phase; float bpm;
    float intensity; float speed; float detail; float glow;
    float4 color0; float4 color1; float4 color2; float4 color3;
  };
  struct CreatorFrame {
    vec2 size; float time; float seedLow; float seedHigh;
    float energy; float bass; float body; float spark;
    float flow; float pulse; float phase; float bpm;
    float intensity; float speed; float detail; float glow;
    vec4 color0; vec4 color1; vec4 color2; vec4 color3;
  };
  struct CatalogShaderVertexOut {
    float4 position [[position]];
    float2 fragCoord [[user(locn0)]];
  };
  """

  static let shaderFooter = """
  fragment float4 creatorFragment(CatalogShaderVertexOut input [[stage_in]],
      constant CreatorUniforms& u [[buffer(0)]]) {
    CreatorFrame f;
    f.size = u.size; f.time = u.time;
    f.seedLow = float(u.seed & 65535u); f.seedHigh = float(u.seed >> 16);
    f.energy = u.energy; f.bass = u.bass; f.body = u.body; f.spark = u.spark;
    f.flow = u.flow; f.pulse = u.pulse; f.phase = u.phase; f.bpm = u.bpm;
    f.intensity = u.intensity; f.speed = u.speed; f.detail = u.detail; f.glow = u.glow;
    f.color0 = u.color0; f.color1 = u.color1; f.color2 = u.color2; f.color3 = u.color3;
    float4 color = paintVisual(input.fragCoord / max(f.size, float2(1.0)), f);
    if (!all(isfinite(color))) return float4(0.0);
    color = clamp(color, 0.0, 1.0);
    return float4(color.rgb * color.a, color.a);
  }
  """
}
