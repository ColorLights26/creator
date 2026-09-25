import Foundation
import Metal
import simd

/// A Dart setFloat stream is densely packed. Each compiler-reflected Metal
/// argument is separate, and float3 arguments require a fourth padding lane.
struct SceneCatalogShaderUniform {
  let name: String
  let location: Int
  let bufferIndex: Int?
  let floatOffset: Int
  let componentCount: Int
  let byteLength: Int
}

struct SceneCatalogShaderDefinition {
  let program: String
  let sourceSHA256: String
  let metalSHA256: String
  let entryPoint: String
  let floatCount: Int
  let uniforms: [SceneCatalogShaderUniform]
  let metalSource: String
}

/// GPU-only runtime for the original catalog fragment programs. Owners serialize
/// calls on their existing scene render queue; this class introduces no clock.
@available(iOS 15.0, *)
final class SceneCatalogShaderRenderer {
  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let vertex: MTLFunction
  private var pipelines: [String: MTLRenderPipelineState] = [:]
  private var multisampleTarget: MTLTexture?
  private static let sampleCount = 4

  init(device: MTLDevice) throws {
    self.device = device
    guard device.supportsTextureSampleCount(Self.sampleCount) else {
      throw RendererError("catalog_shader_sample_count_unsupported")
    }
    guard let queue = device.makeCommandQueue() else {
      throw RendererError("catalog_shader_command_queue_failed")
    }
    self.queue = queue
    let library = try device.makeLibrary(source: Self.vertexSource, options: nil)
    guard let vertex = library.makeFunction(name: "catalogShaderVertex") else {
      throw RendererError("catalog_shader_vertex_missing")
    }
    self.vertex = vertex
  }

  func render(
    program: String,
    uniforms: [Float],
    width: Int,
    height: Int,
    outputAllocator: SceneSurfaceNativeOutputAllocator? = nil
  ) throws -> MTLTexture {
    guard let definition = SceneCatalogShaderSources.programs[program] ?? SceneCreatorCatalog.program(program)?.shader else {
      throw RendererError("catalog_shader_unknown_program: \(program)")
    }
    guard uniforms.count == definition.floatCount,
          uniforms.enumerated().allSatisfy({ offset, value in
            (offset == 3 && SceneCreatorCatalog.program(program) != nil) || value.isFinite
          }),
          uniforms[0] > 0, uniforms[1] > 0 else {
      throw RendererError("catalog_shader_uniforms_invalid: \(program)")
    }
    guard width > 0, height > 0, width <= 8192, height <= 8192 else {
      throw RendererError("catalog_shader_dimensions_invalid")
    }
    let pipeline = try pipeline(for: definition)
    guard let output = try SceneSurfaceNativeOutputAllocator.makeTexture(
      device: device, width: width, height: height, allocator: outputAllocator
    ), let command = queue.makeCommandBuffer() else {
      throw RendererError("catalog_shader_output_unavailable")
    }
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = try multisampleTexture(width: width, height: height)
    pass.colorAttachments[0].resolveTexture = output
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .multisampleResolve
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
    guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
      throw RendererError("catalog_shader_encoder_unavailable")
    }
    encoder.setRenderPipelineState(pipeline)
    // FlutterFragCoord is expressed in logical painter coordinates, independent
    // of the output texture's resolution and the native quality tier.
    var logicalSize = SIMD2<Float>(uniforms[0], uniforms[1])
    encoder.setVertexBytes(&logicalSize, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
    if SceneCreatorCatalog.program(program) != nil {
      uniforms.withUnsafeBufferPointer { buffer in
        encoder.setFragmentBytes(buffer.baseAddress!, length: buffer.count * MemoryLayout<Float>.size, index: 0)
      }
    }
    for uniform in definition.uniforms {
      // The compiler retains dead uniforms in the Dart layout, but removes
      // their Metal arguments. Their float offsets must still be consumed.
      guard let bufferIndex = uniform.bufferIndex else { continue }
      var value = SIMD4<Float>(repeating: 0)
      for component in 0..<uniform.componentCount {
        value[component] = uniforms[uniform.floatOffset + component]
      }
      encoder.setFragmentBytes(&value, length: uniform.byteLength, index: bufferIndex)
    }
    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    encoder.endEncoding()
    command.commit()
    command.waitUntilCompleted()
    guard command.status == .completed else {
      throw command.error ?? RendererError("catalog_shader_command_failed")
    }
    return output
  }

  /// Compile during source preparation, not after the new scene is committed.
  func prepare(program: String) throws {
    guard let definition = SceneCatalogShaderSources.programs[program] ?? SceneCreatorCatalog.program(program)?.shader else {
      throw RendererError("catalog_shader_unknown_program: \(program)")
    }
    _ = try pipeline(for: definition)
  }

  private func multisampleTexture(width: Int, height: Int) throws -> MTLTexture {
    if let target = multisampleTarget, target.width == width, target.height == height {
      return target
    }
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
    )
    descriptor.textureType = .type2DMultisample
    descriptor.sampleCount = Self.sampleCount
    descriptor.usage = .renderTarget
    // Match Impeller's four-sample rasterization without retaining four full
    // images in device memory. The resolved compositor texture stays lossless.
    descriptor.storageMode = device.supportsFamily(.apple1) ? .memoryless : .private
    guard let target = device.makeTexture(descriptor: descriptor) else {
      throw RendererError("catalog_shader_multisample_target_unavailable")
    }
    multisampleTarget = target
    return target
  }

  private func pipeline(for definition: SceneCatalogShaderDefinition) throws -> MTLRenderPipelineState {
    if let pipeline = pipelines[definition.program] { return pipeline }
    let library = try device.makeLibrary(source: definition.metalSource, options: nil)
    guard let fragment = library.makeFunction(name: definition.entryPoint) else {
      throw RendererError("catalog_shader_fragment_missing: \(definition.program)")
    }
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.label = "catalog_shader_\(definition.program)"
    descriptor.rasterSampleCount = Self.sampleCount
    descriptor.vertexFunction = vertex
    descriptor.fragmentFunction = fragment
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    // The original shader already writes its intended premultiplied alpha.
    // Compositing with other layers belongs to the existing scene compositor.
    descriptor.colorAttachments[0].isBlendingEnabled = false
    let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    pipelines[definition.program] = pipeline
    return pipeline
  }

  static let vertexSource = """
  #include <metal_stdlib>
  using namespace metal;
  struct CatalogShaderVertexOut {
    float4 position [[position]];
    float2 fragCoord [[user(locn0)]];
  };
  vertex CatalogShaderVertexOut catalogShaderVertex(
      uint vertexID [[vertex_id]], constant float2& logicalSize [[buffer(0)]]) {
    // Flutter RectGeometry supplies this exact triangle-strip corner order.
    // A full-screen triangle changes interpolation rounding in procedural hashes.
    const float2 uv[4] = { float2(0, 0), float2(1, 0), float2(0, 1), float2(1, 1) };
    CatalogShaderVertexOut out;
    out.position = float4(uv[vertexID].x * 2 - 1, 1 - uv[vertexID].y * 2, 0, 1);
    out.fragCoord = uv[vertexID] * logicalSize;
    return out;
  }
  """

  private struct RendererError: LocalizedError {
    let code: String
    init(_ code: String) { self.code = code }
    var errorDescription: String? { code }
  }
}
