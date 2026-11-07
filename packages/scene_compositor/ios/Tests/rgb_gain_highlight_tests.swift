import CoreGraphics
import CoreImage
import Foundation

// The beat in the bright zones only (`SceneRenderV2HighlightLight`), compiled
// by check_rgb_gain_pulse.py with the production types. A dark room (luma 20
// of 255) with one lamp (150) on 160×284 pixels.

extension RGBGainPulseTests {
  static let roomWidth = 160, roomHeight = 284
  static let lampRect = CGRect(x: 65, y: 127, width: 30, height: 30)
  static let space = CGColorSpace(name: CGColorSpace.sRGB)!
  static let linearContext = CIContext(options: [
    .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
  ])

  static func highlightRecipe(
    low: Double = 0.18, high: Double = 0.45, gain: Double = 1.6, halo: Double = 1.2,
    radius: Double = 0.048, attackMs: Int = 40, releaseMs: Int = 300, drop: String? = nil
  ) -> [String: Any] {
    var parameters = recipe(flow: 0, max: 0.20, pulse: 0, pulseAttackMs: attackMs,
                            pulseReleaseMs: releaseMs)
    var effect = parameters["effect"] as! [String: Any]
    effect["highlightLow"] = low
    effect["highlightHigh"] = high
    effect["highlightGain"] = gain
    effect["highlightHalo"] = halo
    effect["highlightHaloRadius"] = radius
    if let drop { effect[drop] = nil }
    parameters["effect"] = effect
    return parameters
  }

  static func room(lamp: UInt8 = 150) -> CIImage {
    var pixels = [UInt8](repeating: 255, count: roomWidth * roomHeight * 4)
    for y in 0..<roomHeight {
      for x in 0..<roomWidth {
        let inLamp = lampRect.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5))
        let value: UInt8 = inLamp ? lamp : 20
        let p = (y * roomWidth + x) * 4
        pixels[p] = value; pixels[p + 1] = value; pixels[p + 2] = value
      }
    }
    return CIImage(bitmapData: Data(pixels), bytesPerRow: roomWidth * 4,
      size: CGSize(width: roomWidth, height: roomHeight), format: .BGRA8, colorSpace: space)
  }

  /// Green (≈ luma) 8-bit value at pixel (x, y), y from the top.
  static func levels(_ image: CIImage) -> (Int, Int) -> Int {
    var output = [UInt8](repeating: 0, count: roomWidth * roomHeight * 4)
    linearContext.render(image, toBitmap: &output, rowBytes: roomWidth * 4,
      bounds: CGRect(x: 0, y: 0, width: roomWidth, height: roomHeight), format: .BGRA8,
      colorSpace: space)
    return { x, y in Int(output[(y * roomWidth + x) * 4 + 1]) }
  }

  static func runHighlightTests() {
    // Strict V2 reader: all five keys, with the pulse keys, in range.
    let resto = SceneRenderV2RGBGainConfig.decode(highlightRecipe())
    expect(resto?.highlight == SceneRenderV2HighlightLight(
      low: 0.18, high: 0.45, gain: 1.6, halo: 1.2, haloRadius: 0.048) && resto?.followsBeats == true,
      "V2: lee la receta de zonas claras del video aprobado")
    expect(SceneRenderV2RGBGainConfig.decode(highlightRecipe(drop: "highlightHalo")) == nil,
      "V2: rechaza una receta de zonas claras incompleta")
    expect(SceneRenderV2RGBGainConfig.decode(highlightRecipe(gain: 2.1)) == nil &&
      SceneRenderV2RGBGainConfig.decode(highlightRecipe(halo: 2.1)) == nil,
      "V2: rechaza más de 2,0 de golpe o de halo")
    expect(SceneRenderV2RGBGainConfig.decode(highlightRecipe(low: 0.95, high: 1)) == nil &&
      SceneRenderV2RGBGainConfig.decode(highlightRecipe(low: 0.02)) == nil &&
      SceneRenderV2RGBGainConfig.decode(highlightRecipe(low: 0.40, high: 0.42)) == nil,
      "V2: rechaza zonas claras fuera de rango (las oscuras nunca laten)")
    expect(SceneRenderV2RGBGainConfig.decode(highlightRecipe(radius: 0.2)) == nil,
      "V2: rechaza un halo de más del 10 % de la imagen")
    var noPulse = highlightRecipe()
    var noPulseEffect = noPulse["effect"] as! [String: Any]
    for key in ["pulseGain", "pulseAttackMs", "pulseReleaseMs"] { noPulseEffect[key] = nil }
    noPulse["effect"] = noPulseEffect
    expect(SceneRenderV2RGBGainConfig.decode(noPulse) == nil,
      "V2: las zonas claras necesitan las claves del golpe")
    expect(SceneRenderV2RGBGainConfig.decode(recipe(flow: 0.08, max: 0.08))?.highlight == nil,
      "V2: Calm (sin claves de golpe) queda como antes")

    // Tolerant legacy reader: clamps, never rejects keys.
    let legacyEffect = (highlightRecipe(gain: 3, radius: 0.5)["effect"] as! [String: Any])
    let legacy = SceneSurfaceRGBGainEffectRuntime.decode(legacyEffect, pulseLimiter: limiter())
    expect(legacy?.highlight?.gain == 2 && legacy?.highlight?.haloRadius == 0.10,
      "legado: lee las zonas claras y recorta a 2,0 y al 10 %")

    // Light on the frame: lamp and its glow beat, the far room stays.
    guard let highlight = resto?.highlight else { return }
    let source = room()
    expect(highlight.apply(to: source, pulse: 0) === source,
      "sin golpe la imagen es la misma (ningún filtro)")
    let before = levels(source), after = levels(highlight.apply(to: source, pulse: 1))
    let lamp = after(80, 142) - before(80, 142)
    let glow = after(80, 118) - before(80, 118)
    let far = after(10, 10) - before(10, 10)
    print("INFO zonas claras, golpe pleno: lámpara +\(lamp), halo a 9 px +\(glow), rincón lejano +\(far) niveles")
    expect(lamp >= 60, "el golpe sube la lámpara en \(lamp) niveles (el video: unos +50)")
    expect(glow >= 20, "el halo se ve alrededor de la lámpara (+\(glow))")
    expect(abs(far) <= 1, "las zonas oscuras quedan igual (\(far))")
    let halfAfter = levels(highlight.apply(to: source, pulse: 0.5))
    expect(halfAfter(80, 142) - before(80, 142) < lamp,
      "medio golpe da menos luz que un golpe pleno")
    let legacyResto = SceneSurfaceRGBGainEffectRuntime.decode(
      highlightRecipe()["effect"] as! [String: Any], pulseLimiter: limiter())
    expect(legacyResto?.highlight == highlight, "el legado y el V2 leen la misma receta y dan la misma luz")

    // Healing: only the brightest zones, a softer beat.
    let healing = SceneRenderV2RGBGainConfig.decode(highlightRecipe(
      low: 0.62, high: 0.88, gain: 0.7, halo: 0.5, attackMs: 100, releaseMs: 700))!.highlight!
    let dimLamp = levels(healing.apply(to: source, pulse: 1))(80, 142) - before(80, 142)
    let brightSource = room(lamp: 235)
    let brightBefore = levels(brightSource)
    let brightLamp = levels(healing.apply(to: brightSource, pulse: 1))(80, 142) - brightBefore(80, 142)
    let restoBright = levels(highlight.apply(to: room(lamp: 180), pulse: 1))(80, 142) - levels(room(lamp: 180))(80, 142)
    let healingBright = levels(healing.apply(to: room(lamp: 180), pulse: 1))(80, 142) - levels(room(lamp: 180))(80, 142)
    print("INFO healing: lámpara 150 +\(dimLamp), lámpara 235 +\(brightLamp); lámpara 180: healing +\(healingBright), resto +\(restoBright)")
    expect(dimLamp <= 1, "healing: una luz media (150) no late")
    expect(brightLamp > 0 && healingBright < restoBright, "healing: late suave solo en lo más claro")

    // Beats through the V2 state: one ceiling, and the flash rule of the Creator.
    let config = resto!
    let state = SceneRenderV2RGBGainState(config: config, pulseLimiter: limiter())
    var envelope = [Double]()
    for i in 0..<240 {
      now = Int64(i * 33333)
      _ = state.consume(signal(i, beatEvery: 3))
      envelope.append(state.pulseEnvelope)
    }
    let starts = (1..<envelope.count).filter { envelope[$0] - envelope[$0 - 1] > 0.05 &&
      ($0 == 1 || envelope[$0 - 1] - envelope[$0 - 2] <= 0.05) }
    print("INFO zonas claras, 10 golpes/s durante 8 s: \(starts.count) pulsos, peor segundo \(worstSecond(starts))")
    expect(worstSecond(starts) <= 3, "zonas claras: como mucho 3 pulsos por segundo")
    expect(state.gain == 1, "zonas claras: la imagen entera no cambia de ganancia")
    let flash = highlightFlashCheck(config, beatEvery: 3)
    print("INFO flashSafety en un degradado de 16 zonas (20 a 254), 10 golpes/s: peor segundo \(flash.changes) cambios, mayor salto \(fmt(flash.step)) niveles")
    expect(flash.changes <= 6, "flashSafety del Creator: como mucho 6 cambios por segundo")
    let room = roomFlashCheck(config, beatEvery: 3)
    print("INFO flashSafety en la habitación oscura con lámpara: \(room.changes) cambios, mayor salto de zona \(fmt(room.step))")
    expect(room.changes == 0, "flashSafety: una habitación con lámpara nunca cuenta como cambio")
  }

  /// The Creator rule on `apply(to:)` output: 4×4 zones, a change is a frame
  /// in which at least 5 zones move more than 48 levels.
  static func zoneChanges(_ frames: [CIImage], width: Int, height: Int) -> (changes: Int, step: Double) {
    let grid = 4, zoneWidth = width / grid, zoneHeight = height / grid
    var previous = [Double](), changes = [Int](), largest = 0.0
    var output = [UInt8](repeating: 0, count: width * height * 4)
    for (i, frame) in frames.enumerated() {
      linearContext.render(frame, toBitmap: &output, rowBytes: width * 4,
        bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .BGRA8, colorSpace: space)
      var zones = [Double](repeating: 0, count: grid * grid)
      for y in 0..<(zoneHeight * grid) {
        for x in 0..<(zoneWidth * grid) {
          let p = (y * width + x) * 4
          zones[(y / zoneHeight) * grid + x / zoneWidth] +=
            0.0722 * Double(output[p]) + 0.7152 * Double(output[p + 1]) + 0.2126 * Double(output[p + 2])
        }
      }
      zones = zones.map { $0 / Double(zoneWidth * zoneHeight) }
      if !previous.isEmpty {
        let steps = zip(zones, previous).map { abs($0 - $1) }
        largest = max(largest, steps.max()!)
        if steps.filter({ $0 > 48 }).count >= 5 { changes.append(i) }
      }
      previous = zones
    }
    return (worstSecond(changes), largest)
  }

  static func playFrames(_ config: SceneRenderV2RGBGainConfig, source: CIImage, beatEvery k: Int,
                         seconds: Double = 4) -> [CIImage] {
    let state = SceneRenderV2RGBGainState(config: config, pulseLimiter: limiter())
    return (0..<Int(seconds * 30)).map { i in
      now = Int64(i * 33333)
      _ = state.consume(signal(i, beatEvery: k))
      return state.apply(to: source)
    }
  }

  static func highlightFlashCheck(_ config: SceneRenderV2RGBGainConfig, beatEvery k: Int)
    -> (changes: Int, step: Double) {
    let width = 160, height = 284, grid = 4
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        let zone = min(grid - 1, y / (height / grid)) * grid + min(grid - 1, x / (width / grid))
        let value = UInt8(min(254, 20 + zone * 16))
        let p = (y * width + x) * 4
        pixels[p] = value; pixels[p + 1] = value; pixels[p + 2] = value
      }
    }
    let source = CIImage(bitmapData: Data(pixels), bytesPerRow: width * 4,
      size: CGSize(width: width, height: height), format: .BGRA8, colorSpace: space)
    return zoneChanges(playFrames(config, source: source, beatEvery: k), width: width, height: height)
  }

  static func roomFlashCheck(_ config: SceneRenderV2RGBGainConfig, beatEvery k: Int)
    -> (changes: Int, step: Double) {
    zoneChanges(playFrames(config, source: room(), beatEvery: k), width: roomWidth, height: roomHeight)
  }
}
