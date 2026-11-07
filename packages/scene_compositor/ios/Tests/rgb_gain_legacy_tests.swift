import Foundation

// The legacy compositor (iOS production, `SceneSurfaceRGBGainEffectRuntime`),
// compiled by check_rgb_gain_pulse.py from PictureInPictureHandler.swift.
// Audio frames arrive at 60 Hz and a beat is active for one of them; the video
// decodes 24 frames per second and the light is sampled only on those frames.

extension RGBGainPulseTests {
  static let audioFrameMicros: Int64 = 16_667
  static let videoFrameMicros: Int64 = 41_667

  static func legacyRuntime(
    flow: Double, max: Double, pulse: Double? = nil,
    pulseAttackMs: Int = 40, pulseReleaseMs: Int = 350,
    limiter: SceneRenderV2LightPulseLimiter
  ) -> SceneSurfaceRGBGainEffectRuntime {
    var effect: [String: Any] = [
      "kind": "rgb_gain_v1", "flowGain": flow, "sparkGain": 0, "maxGain": max,
      "flowAttackMs": 800, "flowReleaseMs": 2200, "sparkAttackMs": 80,
      "sparkReleaseMs": 550, "framesPerSecond": 24,
    ]
    if let pulse {
      effect["pulseGain"] = pulse
      effect["pulseAttackMs"] = pulseAttackMs
      effect["pulseReleaseMs"] = pulseReleaseMs
    }
    guard let runtime = SceneSurfaceRGBGainEffectRuntime.decode(effect, pulseLimiter: limiter) else {
      fatalError("legacy recipe rejected: \(effect)")
    }
    return runtime
  }

  /// Gain at every video frame for `seconds`, with a beat every
  /// `beatEveryMicros`. `sessionEveryMicros` restarts the audio session
  /// (serials from 1 again) that often.
  static func playLegacy(
    _ runtimes: [SceneSurfaceRGBGainEffectRuntime], beatEveryMicros: Int64,
    seconds: Double = 8, sessionEveryMicros: Int64? = nil, keepImpact: Bool = true
  ) -> [[Double]] {
    var latest = SceneSurfaceReactiveFrame()
    var gains = [[Double]](repeating: [], count: runtimes.count)
    var nextVideo: Int64 = 0
    let end = Int64(seconds * 1_000_000)
    var audio: Int64 = 0
    while audio < end {
      let sessionStart = sessionEveryMicros.map { (audio / $0) * $0 } ?? 0
      let sessionTime = audio - sessionStart
      let beatIndex = sessionTime / beatEveryMicros
      let active = sessionTime % beatEveryMicros < audioFrameMicros
      var next = SceneSurfaceReactiveFrame(arguments: [
        "timestampMicros": NSNumber(value: sessionTime),
        "shouldReact": true,
        "audioSessionId": NSNumber(value: sessionEveryMicros.map { audio / $0 + 1 } ?? 7),
        "impactSerial": NSNumber(value: beatIndex + 1),
        "impactActive": active,
        "impactStrength": NSNumber(value: active ? 0.9 : 0),
        "flowDrive": NSNumber(value: 0),
        "sparkDrive": NSNumber(value: 0),
      ])
      if keepImpact { next.keepImpact(from: latest) }
      latest = next
      audio += audioFrameMicros
      while nextVideo < audio {
        now = nextVideo
        for (index, runtime) in runtimes.enumerated() {
          runtime.sample(frame: latest, hostTime: Double(nextVideo) / 1_000_000)
          gains[index].append(runtime.gain)
        }
        nextVideo += videoFrameMicros
      }
    }
    return gains
  }

  /// Worst number of pulse starts in one second of 24 fps video.
  static func worstVideoSecond(_ frames: [Int]) -> Int {
    var worst = 0, start = 0
    for end in frames.indices {
      while frames[end] - frames[start] >= 24 { start += 1 }
      worst = Swift.max(worst, end - start + 1)
    }
    return worst
  }

  static func runLegacyTests() {
    // Decoding: the legacy reader is tolerant (clamps, never rejects keys).
    let decoded = legacyRuntime(flow: 0.06, max: 0.20, pulse: 0.16, limiter: limiter())
    expect(decoded.pulseGain == 0.16 && decoded.maxGain == 0.20,
      "legado: lee golpes 0,16 y techo 0,20 (antes recortaba a 0,10)")
    expect(legacyRuntime(flow: 0.06, max: 0.30, pulse: 0.30, limiter: limiter()).maxGain == 0.20,
      "legado: nada pasa del techo de 0,20")
    expect(legacyRuntime(flow: 0.06, max: 0.06, limiter: limiter()).pulseGain == 0,
      "legado: receta sin golpes queda como antes")

    // Resto at two beats per second: the beat lifts the light on video frames.
    let rest = legacyRuntime(flow: 0.06, max: 0.20, pulse: 0.16, limiter: limiter())
    let two = playLegacy([rest], beatEveryMicros: 500_000, seconds: 2)[0]
    let peak = two[0..<12].max()!
    print("INFO legado resto, 2 golpes/s a 24 fps: pico \(fmt(peak)) en el cuadro \(two.firstIndex(of: peak)!); 333 ms después \(fmt(two[8]))")
    expect(peak > 1.12 && peak <= 1.20, "legado resto: el golpe sube la luz a \(fmt(peak))")
    expect(pulseStarts(two).count == 4, "legado resto: 4 golpes en 2 s, 4 pulsos")

    // Ten beats per second: the beat held until the next video frame.
    let fast = playLegacy([legacyRuntime(flow: 0.06, max: 0.20, pulse: 0.16, limiter: limiter())],
                          beatEveryMicros: 100_000)[0]
    let fastStarts = pulseStarts(fast)
    let lost = playLegacy([legacyRuntime(flow: 0.06, max: 0.20, pulse: 0.16, limiter: limiter())],
                          beatEveryMicros: 100_000, keepImpact: false)[0]
    print("INFO legado resto, 10 golpes/s durante 8 s: \(fastStarts.count) pulsos, peor segundo \(worstVideoSecond(fastStarts)); sin guardar el golpe saldrían \(pulseStarts(lost).count)")
    expect(worstVideoSecond(fastStarts) <= 3, "legado: como mucho 3 pulsos en cualquier segundo")
    expect(fastStarts.count > 15, "legado: la luz sigue los golpes aunque el video vaya a 24 fps")
    expect(fast.max()! <= 1.20 + 1e-9, "legado: nunca pasa de +20 %")

    // Session change every 267 ms and two layers sharing one ceiling.
    let sessions = playLegacy([legacyRuntime(flow: 0.06, max: 0.20, pulse: 0.16, limiter: limiter())],
                              beatEveryMicros: 100_000, sessionEveryMicros: 266_667)[0]
    let sessionStarts = pulseStarts(sessions)
    print("INFO legado, sesión nueva cada 267 ms: \(sessionStarts.count) pulsos, peor segundo \(worstVideoSecond(sessionStarts))")
    expect(worstVideoSecond(sessionStarts) <= 3, "legado cambio de sesión: como mucho 3 pulsos por segundo real")
    expect(sessionStarts.count > 15, "legado cambio de sesión: la luz sigue los golpes")
    let shared = limiter()
    let pair = playLegacy([legacyRuntime(flow: 0.06, max: 0.20, pulse: 0.16, limiter: shared),
                           legacyRuntime(flow: 0.06, max: 0.20, pulse: 0.16, limiter: shared)],
                          beatEveryMicros: 100_000)
    expect(pair[0] == pair[1], "legado dos capas: la misma luz en el mismo cuadro")
    expect(worstVideoSecond(pulseStarts(pair[0])) <= 3, "legado dos capas: como mucho 3 pulsos por segundo entre las dos")

    // Healing soft; Calm (no beat keys) ignores beats.
    let healing = playLegacy([legacyRuntime(flow: 0.04, max: 0.10, pulse: 0.06, pulseAttackMs: 120,
                                            pulseReleaseMs: 900, limiter: limiter())],
                             beatEveryMicros: 500_000, seconds: 2)[0]
    print("INFO legado healing, 2 golpes/s: pico \(fmt(healing.max()!))")
    expect(healing.max()! > 1.04 && healing.max()! <= 1.06, "legado healing: golpe suave de \(fmt(healing.max()!))")
    let calm = playLegacy([legacyRuntime(flow: 0.08, max: 0.08, limiter: limiter())],
                          beatEveryMicros: 100_000)[0]
    expect(calm.allSatisfy { $0 == 1 }, "legado calm: los golpes no mueven la luz")
  }
}
