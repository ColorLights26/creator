#if canImport(scene_program_native)
import Foundation
import Metal
import CoreGraphics
import simd

@available(iOS 15.0, *)
final class SceneCreatorMaterialRenderer {
  private let renderer: SceneCatalogShaderRenderer
  private let definitions: [SceneCatalogShaderDefinition]
  var count: Int { definitions.count }

  init(device: MTLDevice, definitions source: [String: [String: Any]]) throws {
    renderer = try SceneCatalogShaderRenderer(device: device)
    var result = [SceneCatalogShaderDefinition]()
    for key in source.keys.sorted() {
      guard let item = source[key], let metal = item["metalSource"] as? String,
        let entry = item["entryPoint"] as? String, let count = item["floatCount"] as? Int,
        let hash = item["compilerHash"] as? String, let fields = item["uniforms"] as? [[String: Any]],
        count >= 2, count <= 1026 else { throw SceneCreatorFailure("Invalid material definition: \(key)") }
      var uniforms = [SceneCatalogShaderUniform](), samplers = [SceneCatalogShaderSampler]()
      func binding(_ value: Any?, maximum: Int) throws -> Int? {
        guard let number = value as? NSNumber else { throw SceneCreatorFailure("Invalid material binding") }
        let index = number.int64Value
        if index == 0xffffffff { return nil }
        guard index >= 0, index < maximum else { throw SceneCreatorFailure("Material binding out of range") }
        return Int(index)
      }
      for field in fields {
        if field["sampler"] != nil {
          samplers.append(.init(textureIndex: try binding(field["textureIndex"], maximum: 128), samplerIndex: try binding(field["samplerIndex"], maximum: 16)))
        } else {
          guard let name = field["name"] as? String, let offset = field["offset"] as? Int,
            let components = field["count"] as? Int, (1...4).contains(components), offset >= 0, offset + components <= count else {
            throw SceneCreatorFailure("Invalid material uniform")
          }
          uniforms.append(.init(name: name, location: uniforms.count,
            bufferIndex: try binding(field["bufferIndex"], maximum: 31), floatOffset: offset,
            componentCount: components, byteLength: components == 3 ? 16 : components * 4))
        }
      }
      let definition = SceneCatalogShaderDefinition(program: "material_\(key)_\(hash)", sourceSHA256: hash,
        metalSHA256: hash, entryPoint: entry, floatCount: count, uniforms: uniforms, metalSource: metal, samplers: samplers)
      try renderer.prepare(definition: definition); result.append(definition)
    }
    definitions = result
  }
  func render(index: Int, uniforms: [Float], images: [MTLTexture], width: Int, height: Int) throws -> MTLTexture {
    guard definitions.indices.contains(index) else { throw SceneCreatorFailure("Unknown compiled material") }
    return try renderer.render(definition: definitions[index], uniforms: uniforms, images: images, width: width, height: height)
  }
}

/// Instanced circles: 1,500 stars submit one draw per paint batch, not 1,500
/// paths, blur passes or CPU bitmaps. Gradient coordinates remain local pixels.
@available(iOS 15.0, *)
final class SceneCreatorPointRenderer {
  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let pipelines: [MTLRenderPipelineState]
  init(device: MTLDevice) throws {
    self.device = device
    guard let queue = device.makeCommandQueue() else { throw SceneCreatorFailure("Particle queue unavailable") }
    self.queue = queue
    let library = try device.makeLibrary(source: Self.source, options: nil)
    var pipelines = [MTLRenderPipelineState]()
    for mode in 0...2 {
      let d = MTLRenderPipelineDescriptor(); d.vertexFunction = library.makeFunction(name: "pointVertex")
      d.fragmentFunction = library.makeFunction(name: "pointFragment"); d.colorAttachments[0].pixelFormat = .bgra8Unorm
      let a = d.colorAttachments[0]!
      a.isBlendingEnabled = true; a.sourceRGBBlendFactor = .one; a.sourceAlphaBlendFactor = .one
      a.destinationRGBBlendFactor = mode == 1 ? .one : mode == 2 ? .oneMinusSourceColor : .oneMinusSourceAlpha
      a.destinationAlphaBlendFactor = mode == 1 ? .one : .oneMinusSourceAlpha
      pipelines.append(try device.makeRenderPipelineState(descriptor: d))
    }
    self.pipelines = pipelines
  }
  func render(points: [SIMD2<Float>], radius: Float, paint: SceneCatalogVectorPaint,
              transform t: CGAffineTransform, size: CGSize, width: Int, height: Int) throws -> MTLTexture {
    guard !points.isEmpty, points.count <= 32768,
      let output = try SceneSurfaceNativeOutputAllocator.makeTexture(device: device, width: width, height: height, allocator: nil),
      let command = queue.makeCommandBuffer() else { throw SceneCreatorFailure("Particle output unavailable") }
    let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = output
    pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
    guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw SceneCreatorFailure("Particle encoder unavailable") }
    let blend = paint.blendMode == .plus ? 1 : paint.blendMode == .screen ? 2 : 0
    let gradient = paint.shader
    var parameters: [SIMD4<Float>] = [
      SIMD4(Float(width), Float(height), Float(size.width), Float(size.height)),
      SIMD4(Float(t.a), Float(t.b), Float(t.c), Float(t.d)),
      SIMD4(Float(t.tx), Float(t.ty), radius, 0), paint.color.rgba,
      SIMD4(gradient == nil ? 0 : gradient!.radial ? 2 : 1, Float(gradient?.colors.count ?? 0), gradient?.radius ?? 0, 0),
      SIMD4(gradient?.start.x ?? 0, gradient?.start.y ?? 0, gradient?.end.x ?? 0, gradient?.end.y ?? 0),
    ]
    var colors = [SIMD4<Float>](repeating: .zero, count: 8), stops = [Float](repeating: 0, count: 8)
    if let g = gradient { for i in g.colors.indices { colors[i] = g.colors[i].rgba; stops[i] = Float(g.stops[i]) } }
    guard let buffer = points.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }) else { throw SceneCreatorFailure("Particle buffer unavailable") }
    encoder.setRenderPipelineState(pipelines[blend]); encoder.setVertexBuffer(buffer, offset: 0, index: 1)
    parameters.withUnsafeMutableBytes { encoder.setVertexBytes($0.baseAddress!, length: $0.count, index: 0); encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
    colors.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 2) }
    stops.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 3) }
    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: points.count)
    encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
    guard command.status == .completed else { throw command.error ?? SceneCreatorFailure("Particle GPU command failed") }
    return output
  }
  private static let source = """
  #include <metal_stdlib>
  using namespace metal;
  struct PointOut { float4 position [[position]]; float2 local; float2 offset; };
  vertex PointOut pointVertex(uint v [[vertex_id]], uint i [[instance_id]],
      constant float4* p [[buffer(0)]], const device float2* points [[buffer(1)]]) {
    const float2 corners[4] = {float2(-1,-1),float2(1,-1),float2(-1,1),float2(1,1)};
    PointOut o; float2 d = corners[v] * (p[2].z + 1.0); o.local = points[i] + d; o.offset = d;
    float2 world = float2(p[1].x*o.local.x+p[1].z*o.local.y+p[2].x,
                         p[1].y*o.local.x+p[1].w*o.local.y+p[2].y);
    o.position = float4(world.x/p[0].z*2-1,1-world.y/p[0].w*2,0,1); return o;
  }
  fragment float4 pointFragment(PointOut in [[stage_in]], constant float4* p [[buffer(0)]],
      constant float4* colors [[buffer(2)]], constant float* stops [[buffer(3)]]) {
    float distance = length(in.offset); float aa = max(fwidth(distance), 0.0001);
    float coverage = 1-smoothstep(p[2].z-aa*.5,p[2].z+aa*.5,distance);
    float4 color = p[3];
    if(p[4].x > .5) {
      float2 d=p[5].zw-p[5].xy;
      float t=p[4].x>1.5 ? length(in.local-p[5].xy)/max(p[4].z,.0001)
        : dot(in.local-p[5].xy,d)/max(dot(d,d),.0001);
      color=colors[0];
      for(int i=1;i<int(p[4].y);i++) color=mix(color,colors[i],clamp((t-stops[i-1])/max(stops[i]-stops[i-1],.00001),0.0,1.0));
    }
    return float4(color.rgb*color.a,color.a)*coverage;
  }
  """
}
#endif
