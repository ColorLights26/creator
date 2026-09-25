import Foundation
import CoreGraphics
import CoreFoundation
import Metal

struct SceneCatalogBlueSkyControls: Equatable {
  private(set) var backgroundColor = 0
  private(set) var showClouds = false
  private(set) var cloudColor = 0
  private(set) var numberOfClouds = 7
  private(set) var gradientStop = 0.7

  init?(options: [String: Any], mode: String?) {
    switch mode ?? "default" {
    case "", "default": break
    case "Estándar": showClouds = true
    case "Atardecer":
      backgroundColor = 5; showClouds = true; cloudColor = 2
      numberOfClouds = 10; gradientStop = 0.5
    case "Noche Estrellada":
      backgroundColor = 1; numberOfClouds = 5; gradientStop = 0.9
    default: return nil
    }
    let allowed = Set(["Background Color", "Show Clouds", "Cloud Color", "Number of Clouds", "Gradient Stop"])
    guard Set(options.keys).isSubset(of: allowed) else { return nil }
    for (name, value) in options {
      guard let number = value as? NSNumber else { return nil }
      if name == "Show Clouds" {
        guard CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        showClouds = number.boolValue
        continue
      }
      guard CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
      let scalar = number.doubleValue
      switch name {
      case "Background Color":
        guard (0...7).contains(scalar), scalar.rounded() == scalar else { return nil }
        backgroundColor = Int(scalar)
      case "Cloud Color":
        guard (0...2).contains(scalar), scalar.rounded() == scalar else { return nil }
        cloudColor = Int(scalar)
      case "Number of Clouds":
        guard (1...20).contains(scalar) else { return nil }
        numberOfClouds = Int(scalar)
      case "Gradient Stop":
        guard (0.1...1).contains(scalar) else { return nil }
        gradientStop = scalar
      default: return nil
      }
    }
  }
}

/// Original BlueSky gradient and NightSkyPainter quadratic paths. The host owns
/// the seed and static-source invalidation; this renderer has no timer or feed.
@available(iOS 15.0, *)
final class SceneCatalogBlueSkyRenderer {
  private let renderer: SceneCatalogVectorRenderer
  var lastStatistics: SceneCatalogVectorRenderer.Statistics? { renderer.lastStatistics }

  init(device: MTLDevice) throws { renderer = try SceneCatalogVectorRenderer(device: device) }

  func render(
    controls: SceneCatalogBlueSkyControls, seed: UInt32,
    logicalSize: CGSize, width: Int, height: Int,
    outputAllocator: SceneSurfaceNativeOutputAllocator? = nil
  ) throws -> MTLTexture {
    guard logicalSize.width.isFinite, logicalSize.height.isFinite,
          logicalSize.width > 0, logicalSize.height > 0 else {
      throw NSError(domain: "SceneCatalogBlueSkyRenderer", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "blue_sky_logical_size_invalid"])
    }
    return try renderer.render(canvas: Self.canvas(controls: controls, seed: seed, logicalSize: logicalSize),
      logicalWidth: logicalSize.width, logicalHeight: logicalSize.height,
      width: width, height: height, outputAllocator: outputAllocator)
  }

  static let backgroundColors: [UInt32] = [
    0xFF311B92, 0xFF000000, 0xFF2962FF, 0xFF1A237E,
    0xDD000000, 0xFFEF6C00, 0xFF6A1B9A, 0xFF424242,
  ]
  static let cloudColors: [UInt32] = [0xFF212121, 0xFF616161, 0xFF9E9E9E]

  static func canvas(controls: SceneCatalogBlueSkyControls, seed: UInt32, logicalSize: CGSize) -> SceneCatalogVectorCanvas {
    let canvas = SceneCatalogVectorCanvas()
    let base = backgroundColors[controls.backgroundColor]
    let gradient = SceneCatalogVectorPaint()
    gradient.shader = SceneCatalogVectorLinearGradient(begin: .topCenter, end: .bottomCenter,
      colors: [SceneCatalogVectorColor(darken(base, amount: controls.gradientStop)), SceneCatalogVectorColor(base)])
      .createShader(.fromLTWH(0, 0, logicalSize.width, logicalSize.height))
    canvas.drawRect(.fromLTWH(0, 0, logicalSize.width, logicalSize.height), gradient)
    guard controls.showClouds else { return canvas }
    let cloud = SceneCatalogVectorPaint()
    // Color.withOpacity quantizes alpha to an eight-bit value in the original.
    cloud.color = SceneCatalogVectorColor((cloudColors[controls.cloudColor] & 0x00FFFFFF) | 0xB3000000)
    cloud.maskFilter = .blur(.normal, 10)
    let highlight = SceneCatalogVectorPaint()
    highlight.color = SceneCatalogVectorColor(0x4D000000)
    highlight.maskFilter = .blur(.normal, 5)
    var random = StableRandom(seed: seed)
    for _ in 0..<controls.numberOfClouds {
      let x = random.nextDouble() * logicalSize.width
      let y = random.nextDouble() * logicalSize.height * 0.5
      let width = random.nextDouble() * 300 + 150
      let height = random.nextDouble() * 80 + 40
      let body = SceneCatalogVectorPath()
      body.moveTo(x, y)
      body.quadraticBezierTo(x + width * 0.25, y - height, x + width * 0.5, y)
      body.quadraticBezierTo(x + width * 0.75, y + height, x + width, y)
      body.quadraticBezierTo(x + width * 0.75, y + height * 0.5, x + width * 0.5, y)
      body.quadraticBezierTo(x + width * 0.25, y - height * 0.5, x, y)
      body.close()
      canvas.drawPath(body, cloud)
      let shade = SceneCatalogVectorPath()
      shade.moveTo(x + width * 0.2, y - height * 0.1)
      shade.quadraticBezierTo(x + width * 0.4, y - height * 0.3, x + width * 0.6, y - height * 0.1)
      shade.quadraticBezierTo(x + width * 0.4, y, x + width * 0.2, y - height * 0.1)
      shade.close()
      canvas.drawPath(shade, highlight)
    }
    return canvas
  }

  /// Same HSL lightness subtraction and ARGB rounding as Flutter HSLColor.
  static func darken(_ color: UInt32, amount: Double) -> UInt32 {
    let r = Double((color >> 16) & 255) / 255
    let g = Double((color >> 8) & 255) / 255
    let b = Double(color & 255) / 255
    let highest = max(r, max(g, b)), lowest = min(r, min(g, b))
    let delta = highest - lowest, lightness = (highest + lowest) / 2
    let saturation = delta == 0 ? 0 : min(1, max(0, delta / (1 - abs(2 * lightness - 1))))
    var hue = 0.0
    if delta != 0 {
      if highest == r { hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
      else if highest == g { hue = (b - r) / delta + 2 }
      else { hue = (r - g) / delta + 4 }
      if hue < 0 { hue += 6 }
      hue *= 60
    }
    let adjusted = min(1, max(0, lightness - amount))
    let chroma = (1 - abs(2 * adjusted - 1)) * saturation
    let secondary = chroma * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1))
    let match = adjusted - chroma / 2
    let channels: [Double]
    switch hue {
    case ..<60: channels = [chroma, secondary, 0]
    case ..<120: channels = [secondary, chroma, 0]
    case ..<180: channels = [0, chroma, secondary]
    case ..<240: channels = [0, secondary, chroma]
    case ..<300: channels = [secondary, 0, chroma]
    default: channels = [chroma, 0, secondary]
    }
    let bytes = channels.map { UInt32((($0 + match) * 255).rounded()) }
    return (color & 0xFF000000) | (bytes[0] << 16) | (bytes[1] << 8) | bytes[2]
  }

  // The old painter chose a fresh unseeded Random for each repaint. A scene
  // seed keeps that same distribution stable through resize and reconstruction.
  private struct StableRandom {
    var seed: UInt32
    mutating func nextDouble() -> Double {
      seed = 1_664_525 &* seed &+ 1_013_904_223
      return Double(seed) / 4_294_967_296
    }
  }
}
