import CoreGraphics
import CoreImage
import Foundation

// Compiled by check_rgb_gain_pulse.py with the production rgb_gain_v1 types.
// Signals follow the Creator flash check: 30 fps, a strong low beat (0.9)
// every `beatEvery` frames, every other channel high (0.9).

@main
struct RGBGainPulseTests {
  static var failures = 0
  /// The ceiling's monotonic clock in the tests: each frame sets it.
  static var now: Int64 = 0
  static func limiter() -> SceneRenderV2LightPulseLimiter {
    SceneRenderV2LightPulseLimiter(clock: { RGBGainPulseTests.now })
  }

  static func expect(_ condition: Bool, _ message: String) {
    if condition { print("PASS \(message)"); return }
    failures += 1
    print("FAIL \(message)")
  }

  static func recipe(
    flow: Double, spark: Double = 0, max: Double, pulse: Double? = nil,
    pulseAttackMs: Int = 40, pulseReleaseMs: Int = 350,
    flowAttackMs: Int = 800, flowReleaseMs: Int = 2200
  ) -> [String: Any] {
    var effect: [String: Any] = [
      "kind": "rgb_gain_v1", "flowGain": flow, "sparkGain": spark, "maxGain": max,
      "flowAttackMs": flowAttackMs, "flowReleaseMs": flowReleaseMs,
      "sparkAttackMs": 80, "sparkReleaseMs": 550, "framesPerSecond": 24,
    ]
    if let pulse {
      effect["pulseGain"] = pulse
      effect["pulseAttackMs"] = pulseAttackMs
      effect["pulseReleaseMs"] = pulseReleaseMs
    }
    return ["audioReactive": true, "effect": effect]
  }

  static func config(_ parameters: [String: Any]) -> SceneRenderV2RGBGainConfig {
    guard let decoded = SceneRenderV2RGBGainConfig.decode(parameters) else {
      fatalError("recipe rejected: \(parameters)")
    }
    return decoded
  }

  static func signal(_ sequence: Int, beatEvery k: Int, channels: Float = 0.9,
                     sessionId: Int64 = 2) -> SceneRenderSignalFrameV2 {
    let on = sequence % k == 0, serial = Int64(sequence / k + 1), time = Int64(sequence * 33333)
    let low = SceneRenderSignalEventV2(serial: serial, active: on, timestampMicros: time,
      strength: on ? 0.9 : 0, band: .low)
    let none = SceneRenderSignalEventV2(serial: 0, active: false, timestampMicros: time,
      strength: 0, band: .none)
    return SceneRenderSignalFrameV2(sessionId: sessionId, sequence: Int64(sequence), audioTimestampMicros: time,
      available: true, fresh: true, musicActive: true, tonalAvailable: false,
      dynamics: [Float](repeating: 0.9, count: 6), channels: [Float](repeating: channels, count: 4),
      spectrumSummary: [Float](repeating: 0.9, count: 7), instantSpectrum: [Float](repeating: 0.9, count: 31),
      smoothedSpectrum: [Float](repeating: 0.9, count: 31), semantics: [Float](repeating: 0, count: 6),
      rhythm: [120, 0.5, 0, 0], onsets: [0.9, 0, 0, 0.9], tonal: [0, 0, 0], impact: low, accent: none,
      beat: low, flash: none)
  }

  /// Gains of every frame for `seconds` at 30 fps.
  static func play(_ config: SceneRenderV2RGBGainConfig, beatEvery k: Int, seconds: Double = 8,
                   channels: Float = 0.9) -> [Double] {
    let state = SceneRenderV2RGBGainState(config: config, pulseLimiter: limiter())
    return (0..<Int(seconds * 30)).map { i in
      now = Int64(i * 33333)
      _ = state.consume(signal(i, beatEvery: k, channels: channels))
      return state.gain
    }
  }

  /// First frame of each sharp rise (> +1 % in one frame): a beat lifting the
  /// light. The slow flow never moves that fast.
  static func pulseStarts(_ gains: [Double]) -> [Int] {
    (1..<gains.count).filter { i in
      gains[i] - gains[i - 1] > 0.01 && (i == 1 || gains[i - 1] - gains[i - 2] <= 0.01)
    }
  }

  static func worstSecond(_ frames: [Int]) -> Int {
    var worst = 0, start = 0
    for end in frames.indices {
      while frames[end] - frames[start] >= 30 { start += 1 }
      worst = max(worst, end - start + 1)
    }
    return worst
  }

  /// Creator flashSafety on the production `apply(to:)` (CIColorMatrix):
  /// 160×284, 4×4 zones whose luma goes from 20 to 254, BGRA readback,
  /// Rec. 709 luma per zone, same signals as `play`.
  static func creatorFlashCheck(_ config: SceneRenderV2RGBGainConfig, beatEvery k: Int,
                                seconds: Double = 8) -> (changes: Int, step: Double) {
    let width = 160, height = 284, grid = 4
    let zoneWidth = width / grid, zoneHeight = height / grid
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        let zone = min(grid - 1, y / zoneHeight) * grid + min(grid - 1, x / zoneWidth)
        let value = UInt8(min(254, 20 + zone * 16))
        let p = (y * width + x) * 4
        pixels[p] = value; pixels[p + 1] = value; pixels[p + 2] = value
      }
    }
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let source = CIImage(bitmapData: Data(pixels), bytesPerRow: width * 4,
      size: CGSize(width: width, height: height), format: .BGRA8, colorSpace: space)
    let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!])
    let state = SceneRenderV2RGBGainState(config: config, pulseLimiter: limiter())
    var previous = [Double](), changes = [Int](), largest = 0.0
    var output = [UInt8](repeating: 0, count: width * height * 4)
    for i in 0..<Int(seconds * 30) {
      now = Int64(i * 33333)
      _ = state.consume(signal(i, beatEvery: k))
      context.render(state.apply(to: source), toBitmap: &output, rowBytes: width * 4,
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

  static func fmt(_ value: Double) -> String {
    String(format: "%.3f", value).replacingOccurrences(of: ".", with: ",")
  }

  static func main() {
    // Decoding: older recipes unchanged, pulse keys all-or-nothing, 20 % ceiling.
    expect(SceneRenderV2RGBGainConfig.decode(recipe(flow: 0.06, max: 0.06))?.pulseGain == 0,
      "receta sin golpes se acepta como antes (pulseGain 0)")
    expect(SceneRenderV2RGBGainConfig.decode(recipe(flow: 0.06, max: 0.20, pulse: 0.16)) != nil,
      "receta con golpes 0,16 y techo 0,20 se acepta")
    expect(SceneRenderV2RGBGainConfig.decode(recipe(flow: 0, max: 0.10, pulse: 0.06)) != nil,
      "receta solo con golpes se acepta")
    expect(SceneRenderV2RGBGainConfig.decode(recipe(flow: 0.06, max: 0.21)) == nil,
      "techo 0,21 se rechaza")
    expect(SceneRenderV2RGBGainConfig.decode(recipe(flow: 0.06, max: 0.20, pulse: 0.21)) == nil,
      "golpes 0,21 se rechazan")
    var partial = recipe(flow: 0.06, max: 0.20, pulse: 0.16)
    var effect = partial["effect"] as! [String: Any]
    effect.removeValue(forKey: "pulseReleaseMs")
    partial["effect"] = effect
    expect(SceneRenderV2RGBGainConfig.decode(partial) == nil, "golpes sin todas sus claves se rechazan")

    // Resto: golpes normales. Two beats per second, flow silent.
    let rest = config(recipe(flow: 0.06, max: 0.20, pulse: 0.16))
    let twoPerSecond = play(rest, beatEvery: 15, seconds: 2, channels: 0)
    let peak = twoPerSecond[0..<15].max()!
    let peakFrame = twoPerSecond.firstIndex(of: peak)!
    print("INFO resto, 2 golpes/s: pico \(fmt(peak)) en el cuadro \(peakFrame); a 333 ms \(fmt(twoPerSecond[10])); justo antes del siguiente \(fmt(twoPerSecond[14]))")
    expect(peak > 1.13 && peak <= 1.20, "resto: el golpe sube la luz a \(fmt(peak)) (0,9 × 0,16 = +14,4 %)")
    expect(peakFrame <= 2, "resto: el pico llega en \(peakFrame) cuadros (≤ 67 ms)")
    expect(twoPerSecond[10] < 1 + (peak - 1) * 0.6, "resto: la luz cae suave después del golpe")
    expect(pulseStarts(twoPerSecond).count == 4, "resto: 4 golpes en 2 s, 4 pulsos")

    // Ten beats per second with everything high (the Creator flash signal).
    for (name, cfg) in [("resto", rest),
                        ("resto con golpes al máximo 0,20", config(recipe(flow: 0.10, max: 0.20, pulse: 0.20)))] {
      let gains = play(cfg, beatEvery: 3)
      let starts = pulseStarts(gains)
      let worst = worstSecond(starts)
      let flash = creatorFlashCheck(cfg, beatEvery: 3)
      print("INFO \(name), 10 golpes/s durante 8 s: \(starts.count) pulsos, peor segundo \(worst); máximo \(fmt(gains.max()!)); Creator: \(flash.changes) cambios en el peor segundo, mayor salto de zona \(String(format: "%.1f", flash.step)) niveles")
      expect(worst <= 3, "\(name): como mucho 3 pulsos en cualquier segundo (\(worst))")
      expect(gains.max()! <= 1.20 + 1e-9, "\(name): nunca pasa del techo de +20 %")
      expect(flash.changes == 0, "\(name): flashSafety del Creator, 0 cambios grandes (máx 6)")
      expect(flash.step < 20.5, "\(name): ningún cuadro mueve una zona más de 20 niveles")
    }

    // Healing: golpes suaves, caída lenta, techo +10 %.
    let healing = config(recipe(flow: 0.06, max: 0.10, pulse: 0.06, pulseAttackMs: 120,
      pulseReleaseMs: 900, flowAttackMs: 1200, flowReleaseMs: 3000))
    let healingGains = play(healing, beatEvery: 15, seconds: 2, channels: 0)
    let healingPeak = healingGains[0..<15].max()!
    print("INFO healing, 2 golpes/s: pico \(fmt(healingPeak)); a 333 ms \(fmt(healingGains[10]))")
    expect(healingPeak > 1.04 && healingPeak <= 1.06, "healing: golpe suave de \(fmt(healingPeak))")
    expect(play(healing, beatEvery: 3).max()! <= 1.10 + 1e-9, "healing: nunca pasa de +10 %")

    // Calm: sin golpes, lenta y baja.
    let calm = config(recipe(flow: 0.08, max: 0.08, flowAttackMs: 1500, flowReleaseMs: 3500))
    let calmGains = play(calm, beatEvery: 3, seconds: 8)
    let calmSteps = zip(calmGains.dropFirst(), calmGains).map { abs($0 - $1) }
    print("INFO calm, 10 golpes/s: máximo \(fmt(calmGains.max()!)), mayor cambio entre cuadros \(String(format: "%.4f", calmSteps.max()!))")
    expect(pulseStarts(calmGains).count <= 1, "calm: los golpes no mueven la luz")
    expect(calmGains.max()! <= 1.08 + 1e-9, "calm: nunca pasa de +8 %")

    // A new audio session restarts the audio clock and the serials every
    // 8 frames while real time runs on: the ceiling must not reopen. Before
    // 06-11 this let a pulse through at every session change.
    let sessions = SceneRenderV2RGBGainState(config: rest, pulseLimiter: limiter())
    let sessionGains: [Double] = (0..<240).map { i in
      now = Int64(i * 33333)
      _ = sessions.consume(signal(i % 8, beatEvery: 3, sessionId: Int64(i / 8 + 1)))
      return sessions.gain
    }
    let sessionStarts = pulseStarts(sessionGains)
    print("INFO resto, sesión nueva cada 267 ms con 10 golpes/s: \(sessionStarts.count) pulsos en 8 s, peor segundo \(worstSecond(sessionStarts))")
    expect(worstSecond(sessionStarts) <= 3, "cambio de sesión: como mucho 3 pulsos en cualquier segundo real")
    expect(sessionStarts.count > 15, "cambio de sesión: la luz sigue los golpes")

    // Two reactive layers of one scene share one window and pulse together.
    let shared = limiter()
    let layers = [SceneRenderV2RGBGainState(config: rest, pulseLimiter: shared),
                  SceneRenderV2RGBGainState(config: rest, pulseLimiter: shared)]
    var layerGains: [[Double]] = [[], []]
    for i in 0..<240 {
      now = Int64(i * 33333)
      for (index, layer) in layers.enumerated() {
        _ = layer.consume(signal(i, beatEvery: 3))
        layerGains[index].append(layer.gain)
      }
    }
    let layerStarts = pulseStarts(layerGains[0])
    print("INFO dos capas, 10 golpes/s: \(layerStarts.count) pulsos cada una, peor segundo \(worstSecond(layerStarts))")
    expect(layerGains[0] == layerGains[1], "dos capas: la misma luz en el mismo cuadro")
    expect(worstSecond(layerStarts) <= 3, "dos capas: como mucho 3 pulsos en cualquier segundo entre las dos")

    runLegacyTests()
    runHighlightTests()

    // Silence: music stops, the light returns to exact identity.
    let state = SceneRenderV2RGBGainState(config: rest, pulseLimiter: limiter())
    for i in 0..<30 { now = Int64(i * 33333); _ = state.consume(signal(i, beatEvery: 3)) }
    for i in 30..<930 {
      now = Int64(i * 33333)
      let s = signal(i, beatEvery: 1000, channels: 0)
      _ = state.consume(SceneRenderSignalFrameV2(sessionId: 2, sequence: s.sequence,
        audioTimestampMicros: s.audioTimestampMicros, available: true, fresh: true, musicActive: false,
        tonalAvailable: false, dynamics: s.dynamics, channels: s.channels, spectrumSummary: s.spectrumSummary,
        instantSpectrum: s.instantSpectrum, smoothedSpectrum: s.smoothedSpectrum, semantics: s.semantics,
        rhythm: s.rhythm, onsets: s.onsets, tonal: s.tonal, impact: s.impact, accent: s.accent,
        beat: s.beat, flash: s.flash))
    }
    expect(state.gain == 1, "sin música la luz vuelve exacta a 1 (\(state.gain))")

    print(failures == 0 ? "ALL PASS" : "\(failures) FAIL")
    exit(failures == 0 ? 0 : 1)
  }
}
