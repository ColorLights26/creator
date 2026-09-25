import Foundation
import CoreGraphics
import Metal

/// Faithful MagicClouds Canvas port: seven seeded union masks, cached by size,
/// and the original three tiled drifts. The compositor supplies active elapsed time.
@available(iOS 15.0, *)
final class SceneCatalogCloudRenderer {
  struct Formation {
    let center: CGPoint
    let width: Double
    let height: Double
    let cycle: Double
    let colors: [UInt32]
    let ellipses: [CGRect]

    var bounds: CGRect {
      ellipses.reduce(CGRect.null) { $0.union($1) }
    }

    var body: CGPath {
      let path = CGMutablePath()
      for ellipse in ellipses { path.addEllipse(in: ellipse) }
      // One nonzero-winding fill is the union of these equally oriented ovals.
      // Separate translucent ellipse draws would incorrectly darken overlaps.
      return path
    }
  }

  struct Placement {
    let formation: Int
    let center: CGPoint
  }

  private struct Mask {
    let texture: MTLTexture
    let localBounds: CGRect
  }

  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let pipeline: MTLRenderPipelineState
  private var masks: [Mask] = []
  private var maskWidth = 0
  private var maskHeight = 0
  private(set) var maskRasterizationCount = 0

  init(device: MTLDevice) throws {
    self.device = device
    guard let queue = device.makeCommandQueue() else { throw RendererError("cloud_queue_failed") }
    self.queue = queue
    let library = try device.makeLibrary(source: Self.metalSource, options: nil)
    guard let vertex = library.makeFunction(name: "cloudVertex"),
          let fragment = library.makeFunction(name: "cloudFragment") else {
      throw RendererError("cloud_shader_failed")
    }
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = vertex
    descriptor.fragmentFunction = fragment
    let attachment = descriptor.colorAttachments[0]!
    attachment.pixelFormat = .bgra8Unorm
    attachment.isBlendingEnabled = true
    attachment.rgbBlendOperation = .add
    attachment.alphaBlendOperation = .add
    attachment.sourceRGBBlendFactor = .one
    attachment.sourceAlphaBlendFactor = .one
    attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
    attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
  }

  func render(
    elapsed: Double, width: Int, height: Int,
    outputAllocator: SceneSurfaceNativeOutputAllocator? = nil
  ) throws -> MTLTexture {
    guard elapsed.isFinite, elapsed >= 0, width > 0, height > 0,
          width <= 8192, height <= 8192 else { throw RendererError("cloud_input_invalid") }
    try prepareMasks(width: width, height: height)
    guard let output = try SceneSurfaceNativeOutputAllocator.makeTexture(
      device: device, width: width, height: height, allocator: outputAllocator),
      let command = queue.makeCommandBuffer() else { throw RendererError("cloud_target_failed") }
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = output
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
    guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
      throw RendererError("cloud_encoder_failed")
    }
    encoder.setRenderPipelineState(pipeline)
    var viewport = SIMD2<Float>(Float(width), Float(height))
    encoder.setVertexBytes(&viewport, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
    let scaleX = Double(width) / 1000
    let scaleY = Double(height) / 1800
    for placement in Self.placements(elapsed: elapsed) {
      let shape = Self.formations[placement.formation]
      let mask = masks[placement.formation]
      var rect = SIMD4<Float>(
        Float((placement.center.x + mask.localBounds.minX) * scaleX),
        Float((placement.center.y + mask.localBounds.minY) * scaleY),
        Float(mask.localBounds.width * scaleX), Float(mask.localBounds.height * scaleY))
      var gradient = SIMD2<Float>(Float((mask.localBounds.minY + shape.height * 0.65) / shape.height),
                                 Float(mask.localBounds.height / shape.height))
      let colors = shape.colors.map(Self.color)
      encoder.setVertexBytes(&rect, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
      encoder.setFragmentBytes(&gradient, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
      colors.withUnsafeBytes { bytes in
        encoder.setFragmentBytes(bytes.baseAddress!, length: bytes.count, index: 1)
      }
      encoder.setFragmentTexture(mask.texture, index: 0)
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }
    encoder.endEncoding()
    command.commit()
    command.waitUntilCompleted()
    guard command.status == .completed else { throw command.error ?? RendererError("cloud_gpu_failed") }
    return output
  }

  static func placements(elapsed: Double) -> [Placement] {
    var result: [Placement] = []
    // Match field order, then tile order, then formation order from the painter.
    for range in [0..<3, 3..<5, 5..<7] {
      let cycle = formations[range.lowerBound].cycle
      let micros = floor(elapsed * 1_000_000)
      let drift = -(micros.truncatingRemainder(dividingBy: cycle * 1_000_000) /
                    (cycle * 1_000_000)) * 1560
      for tile in -1...2 {
        for index in range {
          let shape = formations[index]
          let x = drift + Double(tile) * 1560 + shape.center.x
          let radius = shape.width * 0.72
          if x + radius < -40 || x - radius > 1040 { continue }
          result.append(Placement(formation: index, center: CGPoint(x: x, y: shape.center.y)))
        }
      }
    }
    return result
  }

  private func prepareMasks(width: Int, height: Int) throws {
    if width == maskWidth, height == maskHeight, masks.count == Self.formations.count { return }
    let scaleX = Double(width) / 1000
    let scaleY = Double(height) / 1800
    var prepared: [Mask] = []
    for shape in Self.formations {
      let bounds = shape.bounds
      let originX = floor(bounds.minX * scaleX) - 1
      let originY = floor(bounds.minY * scaleY) - 1
      let pixelsWide = Int(ceil(bounds.maxX * scaleX) + 1 - originX)
      let pixelsHigh = Int(ceil(bounds.maxY * scaleY) + 1 - originY)
      guard let context = CGContext(data: nil, width: pixelsWide, height: pixelsHigh,
        bitsPerComponent: 8, bytesPerRow: pixelsWide, space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue), let bytes = context.data else {
        throw RendererError("cloud_mask_failed")
      }
      context.setAllowsAntialiasing(true)
      context.setShouldAntialias(true)
      // Bitmap memory/Metal UV row zero is the top; Canvas's positive Y points
      // down, unlike the default CoreGraphics bitmap coordinate system.
      context.translateBy(x: 0, y: CGFloat(pixelsHigh))
      context.scaleBy(x: 1, y: -1)
      context.translateBy(x: -originX, y: -originY)
      context.scaleBy(x: scaleX, y: scaleY)
      context.addPath(shape.body)
      context.setFillColor(gray: 1, alpha: 1)
      context.drawPath(using: .fill)
      let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm,
        width: pixelsWide, height: pixelsHigh, mipmapped: false)
      descriptor.storageMode = .shared
      descriptor.usage = .shaderRead
      guard let texture = device.makeTexture(descriptor: descriptor) else {
        throw RendererError("cloud_mask_texture_failed")
      }
      texture.replace(region: MTLRegionMake2D(0, 0, pixelsWide, pixelsHigh), mipmapLevel: 0,
        withBytes: bytes, bytesPerRow: pixelsWide)
      prepared.append(Mask(texture: texture, localBounds: CGRect(x: originX / scaleX,
        y: originY / scaleY, width: Double(pixelsWide) / scaleX, height: Double(pixelsHigh) / scaleY)))
    }
    masks = prepared
    maskWidth = width; maskHeight = height
    maskRasterizationCount += prepared.count
  }

  private static func color(_ argb: UInt32) -> SIMD4<Float> {
    SIMD4(Float((argb >> 16) & 255) / 255, Float((argb >> 8) & 255) / 255,
          Float(argb & 255) / 255, Float((argb >> 24) & 255) / 255)
  }

  private struct RendererError: LocalizedError {
    let code: String
    init(_ code: String) { self.code = code }
    var errorDescription: String? { code }
  }

  private static let metalSource = #"""
    #include <metal_stdlib>
    using namespace metal;
    struct CloudVertex { float4 position [[position]]; float2 uv; };
    vertex CloudVertex cloudVertex(uint id [[vertex_id]], constant float4 &rect [[buffer(0)]],
                                    constant float2 &viewport [[buffer(1)]]) {
      constexpr float2 uv[6] = { float2(0,0),float2(1,0),float2(0,1),
                                float2(0,1),float2(1,0),float2(1,1) };
      float2 pixel = rect.xy + uv[id] * rect.zw;
      return { float4(pixel.x / viewport.x * 2 - 1, 1 - pixel.y / viewport.y * 2, 0, 1), uv[id] };
    }
    fragment float4 cloudFragment(CloudVertex input [[stage_in]],
      constant float2 &gradient [[buffer(0)]], constant float4 *colors [[buffer(1)]],
      texture2d<float> mask [[texture(0)]]) {
      constexpr sampler sampleMask(coord::normalized, address::clamp_to_edge, filter::linear);
      float t = clamp(gradient.x + input.uv.y * gradient.y, 0.0, 1.0);
      float4 color = t < 0.48 ? mix(colors[0], colors[1], t / 0.48)
                                 : mix(colors[1], colors[2], (t - 0.48) / 0.52);
      float alpha = color.a * mask.sample(sampleMask, input.uv).r;
      return float4(color.rgb * alpha, alpha);
    }
    """#

  // Generated offline from magic_clouds.dart Random seeds by --emit-swift.
  static let formations: [Formation] = [
    Formation(center: CGPoint(x: 876.8994252215961, y: 399.3465961609491), width: 177.06355410044222, height: 58.36479861362784, cycle: 92, colors: [406340456, 270938192, 134679325], ellipses: [
      CGRect(x: -78.7287805324769, y: 0.8754719792044181, width: 157.4575610649538, height: 16.92579159795207),
      CGRect(x: -94.35666435698457, y: -14.248181547441009, width: 68.23624341639305, height: 31.514793486702978),
      CGRect(x: -68.595875859954, y: -21.8299924209398, width: 77.66898829014546, height: 39.276273399433876),
      CGRect(x: -32.54447938433698, y: -19.03824019842598, width: 54.686104444725174, height: 32.64788895795758),
      CGRect(x: 9.191497768820078, y: -18.234555997613846, width: 53.856880429166964, height: 31.08708116124363),
      CGRect(x: 26.54319843441695, y: -10.335608604382129, width: 73.7255391093189, height: 27.48471655706399)
    ]),
    Formation(center: CGPoint(x: 347.94356921706276, y: 782.286666829655), width: 191.40217671538642, height: 97.91225845823413, cycle: 92, colors: [406340456, 270938192, 134679325], ellipses: [
      CGRect(x: -84.15276406746683, y: 1.4686838768735129, width: 168.30552813493367, height: 28.394554952887898),
      CGRect(x: -114.29212190415583, y: -12.876370878014127, width: 73.97398930179514, height: 37.18150474910438),
      CGRect(x: -75.15766118346313, y: -31.727983597387098, width: 88.61550294431822, height: 55.50316539491924),
      CGRect(x: -11.982429346704478, y: -30.764122269994893, width: 92.09935654532322, height: 57.9282849192982),
      CGRect(x: 2.6282149706252085, y: -18.23459122724655, width: 112.04222014763064, height: 39.261119048592676)
    ]),
    Formation(center: CGPoint(x: 727.4039138700706, y: 1328.7243153558054), width: 218.1984477362507, height: 65.45290436685544, cycle: 92, colors: [406340456, 270938192, 134679325], ellipses: [
      CGRect(x: -99.33545276500136, y: -3.2726452183427703, width: 198.67090553000273, height: 27.49021983407928),
      CGRect(x: -131.5103507624513, y: -3.2933517916382264, width: 61.40963893358021, height: 19.385582349394415),
      CGRect(x: -95.17698686267485, y: -17.821229740416875, width: 82.16779773262405, height: 36.30352486913578),
      CGRect(x: -62.705630096488115, y: -32.730961959448535, width: 77.86654895861578, height: 52.892661934803556),
      CGRect(x: -37.62983582313891, y: -38.58046672111074, width: 90.08940126797823, height: 53.817528850132526),
      CGRect(x: 6.750434759113546, y: -19.093777625147773, width: 107.06673365555159, height: 36.69430354638159),
      CGRect(x: 32.575860552513596, y: -5.726319209987743, width: 97.0650716841512, height: 21.61282662163729)
    ]),
    Formation(center: CGPoint(x: 759.1620169424103, y: 536.0025724109553), width: 371.22384270442836, height: 151.39886598114663, cycle: 67, colors: [574902130, 405813849, 218697252], ellipses: [
      CGRect(x: -169.44878250966514, y: -7.569943299057332, width: 338.8975650193303, height: 63.58752371208158),
      CGRect(x: -247.0486237165038, y: -25.484894649745442, width: 220.686291775371, height: 66.79552210254577),
      CGRect(x: -144.7723711157309, y: -65.43809752485838, width: 182.70538778260072, height: 99.92568098200009),
      CGRect(x: -15.131582201920168, y: -55.55157081099609, width: 170.34757524150763, height: 93.93590710682619),
      CGRect(x: 6.12564745687996, y: -35.120099836746896, width: 228.42678225654078, height: 76.25623918248748)
    ]),
    Formation(center: CGPoint(x: 743.0543273016096, y: 1052.3303756269588), width: 267.75993688867, height: 108.85412641892914, cycle: 67, colors: [574902130, 405813849, 218697252], ellipses: [
      CGRect(x: -112.72189493479318, y: -2.1770825283785804, width: 225.44378986958637, height: 39.18748551081448),
      CGRect(x: -151.45688110156658, y: -8.069083085439651, width: 60.94008512766767, height: 36.1635194611514),
      CGRect(x: -118.92588782115706, y: -44.34985795338798, width: 81.01053736969016, height: 73.73561839359333),
      CGRect(x: -78.4947036027689, y: -60.49310335854737, width: 71.71654694957874, height: 91.99341562806971),
      CGRect(x: -66.48789551430241, y: -48.140909034692214, width: 98.88592648973778, height: 77.17128847574598),
      CGRect(x: -30.64752242215618, y: -32.94695687806303, width: 80.77555913726103, height: 62.56595833119832),
      CGRect(x: 2.350411050787727, y: -18.155411608161565, width: 92.8813128687915, height: 49.19364259074208),
      CGRect(x: 50.87757255972747, y: -8.925624009510189, width: 80.9855401021893, height: 37.5075392374927),
      CGRect(x: 96.43218752448195, y: -5.120061888712687, width: 61.226814901021555, height: 33.9098668472245)
    ]),
    Formation(center: CGPoint(x: 682.8892021199645, y: 320.36392405286927), width: 588.5418498366852, height: 126.577666821553, cycle: 49, colors: [760438912, 574178144, 336203817], ellipses: [
      CGRect(x: -262.60884797857176, y: -6.328883341077649, width: 525.2176959571435, height: 53.16262006505226),
      CGRect(x: -402.381729829614, y: -23.462928209996527, width: 395.89356694810726, height: 49.27625508666229),
      CGRect(x: -214.3866221586334, y: -57.179213260920825, width: 260.9418663163531, height: 88.33333711101423),
      CGRect(x: -34.45229952091758, y: -50.186294747696806, width: 255.3746704379863, height: 82.95338638297369),
      CGRect(x: 21.13175334310182, y: -24.52020856012998, width: 310.8652713882999, height: 56.28173462703608)
    ]),
    Formation(center: CGPoint(x: 923.2662488753316, y: 1380.9256667283973), width: 482.74123676234655, height: 206.08665936623345, cycle: 49, colors: [760438912, 574178144, 336203817], ellipses: [
      CGRect(x: -226.32478293732072, y: 3.091299890493506, width: 452.64956587464144, height: 59.765131216207706),
      CGRect(x: -303.0338963362717, y: -33.052878780828664, width: 208.7584498834722, height: 81.86651942895534),
      CGRect(x: -185.33521027059567, y: -83.21426352206042, width: 222.69530851089894, height: 144.38241124870515),
      CGRect(x: -94.91030405545338, y: -78.12357867692478, width: 149.744453939951, height: 116.05314060619598),
      CGRect(x: 42.323044860375305, y: -51.06626238368764, width: 141.83144608181448, height: 88.67972277346625),
      CGRect(x: 92.48179225012012, y: -22.3453305557966, width: 211.67002567393916, height: 64.53209583062107)
    ])
  ]
}
