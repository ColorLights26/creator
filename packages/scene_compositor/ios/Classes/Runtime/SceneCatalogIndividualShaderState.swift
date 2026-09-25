import Foundation
import CoreGraphics

/// State authority for the nine individual catalog shaders. Uniform order and
/// constants follow the corresponding audiovisuals/lib/{backgrounds,transparents}
/// Dart implementation. The owning SceneSurface supplies time and signals.
final class SceneCatalogIndividualShaderState {
  private struct Configuration {
    // Mode: palette index, motion, then the authored non-audio shader controls.
    let controls: [String]
    let ranges: [ClosedRange<Double>]
    let modes: [String: [Double]]
    let nonReactiveModes: Set<String>
    let palettes: [[UInt32]]
    let paletteSeconds: Double
    // bass, body, spark, energy, flow, optional groove attack/release pairs.
    let envelope: [(Double, Double)]
    let energyIntensity: Double
    let flowMix: (Double, Double)
    let flowUsesBody: Bool
    let beatSeconds: Double
    let speed: [Double] // constant, flow, groove, bass, beat; common is multiplicative
    let motionRange: ClosedRange<Double>
    let overlay: Bool
  }

  let program: String
  private let configuration: Configuration
  private let motion: Double
  private let controls: [Double]
  private let reactive: Bool
  private let targetPalette: [Double]
  private var displayPalette: [Double]
  private var playing = false
  private var lastHostTime: Double?
  private var visualTime = 0.0
  private var envelope = [Double](repeating: 0, count: 7)
  private var signal: SceneRenderSignalFrameV2?
  private var pulseAge = 2.0
  private var pulseSeed = 0.0
  private var hitPending = false

  init?(program: String, options: [String: Any], mode: String?) {
    guard let configuration = Self.configurations[program] else { return nil }
    let selectedMode = configuration.modes[mode ?? "default"] != nil
      ? (mode ?? "default") : "default"
    guard let values = configuration.modes[selectedMode] else { return nil }
    let allowed = Set(configuration.controls + ["Palette", "Motion", "Music Reactive"])
    guard Set(options.keys).isSubset(of: allowed) else { return nil }
    func number(_ name: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Double? {
      guard let raw = options[name] else { return fallback }
      guard let value = raw as? NSNumber,
            CFGetTypeID(value) != CFBooleanGetTypeID(),
            value.doubleValue.isFinite, range.contains(value.doubleValue)
      else { return nil }
      return value.doubleValue
    }
    guard let palette = number("Palette", values[0], 0...3),
          palette.rounded(.towardZero) == palette,
          let motion = number("Motion", values[1], configuration.motionRange)
    else { return nil }
    var controls: [Double] = []
    for (index, name) in configuration.controls.enumerated() {
      guard let value = number(name, values[index + 2], configuration.ranges[index])
      else { return nil }
      controls.append(value)
    }
    let reactive: Bool
    if let raw = options["Music Reactive"] {
      guard let value = raw as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID()
      else { return nil }
      reactive = value.boolValue
    } else {
      reactive = !configuration.nonReactiveModes.contains(selectedMode)
    }
    self.program = program
    self.configuration = configuration
    self.motion = motion
    self.controls = controls
    self.reactive = reactive
    self.targetPalette = Self.components(configuration.palettes[Int(palette)])
    // The original starts with the first palette, then blends toward the mode.
    self.displayPalette = Self.components(configuration.palettes[0])
  }

  @discardableResult
  func consume(_ frame: SceneRenderSignalFrameV2) -> Bool {
    guard signal != frame else { return false }
    // The transport's event-preserving dispatcher may repeat a serial while
    // delivering a new state. Original overlay onFrame counts active callbacks,
    // while _nextFrame consumes all callbacks since the last paint as one hit.
    if configuration.overlay && frame.flash.active { hitPending = true }
    signal = frame
    return true
  }

  func inheritAnimation(from previous: SceneCatalogIndividualShaderState) {
    displayPalette = previous.displayPalette
    playing = previous.playing
    lastHostTime = previous.lastHostTime
    visualTime = previous.visualTime
    envelope = reactive ? previous.envelope : [Double](repeating: 0, count: 7)
    signal = previous.signal
    pulseAge = previous.pulseAge
    pulseSeed = previous.pulseSeed
    hitPending = previous.hitPending
  }

  func setPlaying(_ value: Bool, hostTime: Double) {
    guard value != playing else { return }
    playing = value
    lastHostTime = hostTime.isFinite ? hostTime : nil
    if !value { envelope = [Double](repeating: 0, count: 7) }
  }

  func uniforms(size: CGSize, hostTime: Double, reducedMotion: Bool) -> [Float] {
    // None of these nine original shaders scales its equations for Reduce
    // Motion. The shared scene cadence/signal safety authority already applies
    // that policy; multiplying the local clock again would change the effect.
    let defaultDelta = (program == "neon_overdrive" || program == "prismatic_sanctuary")
      ? 0.016666 : 0.033333
    let delta = hostTime.isFinite
      ? min(0.05, max(0, lastHostTime.map { hostTime - $0 } ?? defaultDelta)) : 0
    if hostTime.isFinite { lastHostTime = hostTime }
    if playing {
      if configuration.overlay {
        if reactive && hitPending {
          hitPending = false
          pulseAge = 0
          pulseSeed = (pulseSeed + 1).truncatingRemainder(dividingBy: 997)
        }
        pulseAge = min(2, pulseAge + delta)
      }
      updateEnvelope(delta: delta)
      let speed = configuration.speed
      let factor: Double
      if program == "neon_overdrive" {
        factor = speed[0] + envelope[5] * speed[1] + envelope[6] * speed[2]
          + envelope[0] * speed[3] + envelope[3] * speed[4]
      } else {
        factor = speed[0] * (1 + envelope[5] * speed[1]
          + envelope[6] * speed[2] + envelope[1] * speed[3] + envelope[3] * speed[4])
      }
      visualTime += delta * motion * factor
      let amount = 1 - exp(-delta / configuration.paletteSeconds)
      for index in displayPalette.indices {
        displayPalette[index] += (targetPalette[index] - displayPalette[index]) * amount
      }
    } else {
      envelope = [Double](repeating: 0, count: 7)
    }
    var result = [Double(size.width), Double(size.height), visualTime]
    result += Array(envelope.prefix(6))
    if configuration.envelope.count == 6 { result.append(envelope[6]) }
    if configuration.overlay { result += [pulseAge, pulseSeed] }
    result += controls
    result.append(reactive ? 1 : 0)
    // Dart Color.lerp retains floating channels, but _setColor calls toARGB32
    // before uploading each frame. Preserve that quantization, not float RGB.
    result += displayPalette.map { $0.rounded() / 255 }
    return result.map(Float.init)
  }

  private func updateEnvelope(delta: Double) {
    let frame = reactive ? signal : nil
    // VisualAudioBinding supplies forMusicReaction(), hence all of these
    // channels/events are zero when !shouldReact. Neon's presence-dependent
    // reactionGate would then multiply only zeros. For confirmed music it is 1.
    let active = frame.map { $0.available && $0.musicActive } ?? false
    func channel(_ index: Int) -> Double {
      guard active, let frame, frame.channels.indices.contains(index) else { return 0 }
      return Double(frame.channels[index])
    }
    func dynamic(_ index: Int) -> Double {
      guard active, let frame, frame.dynamics.indices.contains(index) else { return 0 }
      return Double(frame.dynamics[index])
    }
    let groove = active && (frame?.rhythm.count ?? 0) > 3 ? Double(frame!.rhythm[3]) : 0
    let impact = active ? Double(frame?.impact.strength ?? 0) : 0
    let flash = active ? Double(frame?.flash.strength ?? 0) : 0
    let targets = [
      Self.unit(channel(0)), Self.unit(channel(1)), Self.unit(channel(2)),
      Self.unit(max(dynamic(3), dynamic(2) * configuration.energyIntensity)),
      Self.unit(channel(3) * configuration.flowMix.0
        + (configuration.flowUsesBody ? channel(1) : groove) * configuration.flowMix.1),
      Self.unit(groove)
    ]
    let slots = [0, 1, 2, 4, 5, 6]
    for (index, timing) in configuration.envelope.enumerated() {
      let slot = slots[index]
      let target = targets[index]
      let tau = target > envelope[slot] ? timing.0 : timing.1
      envelope[slot] += (target - envelope[slot]) * (1 - exp(-delta / tau))
    }
    if program == "neon_overdrive" {
      envelope[3] *= exp(-delta / 0.12)
      if active && frame?.flash.active == true && flash > 0.28 {
        envelope[3] = max(envelope[3], sqrt(flash))
      } else {
        envelope[3] = max(envelope[3], impact * 0.34)
      }
    } else {
      envelope[3] = max(Self.unit(max(impact, flash)),
        envelope[3] * exp(-delta / configuration.beatSeconds))
    }
  }

  private static func unit(_ value: Double) -> Double { min(1, max(0, value)) }
  private static func components(_ colors: [UInt32]) -> [Double] {
    colors.flatMap { color in
      [Double((color >> 16) & 255), Double((color >> 8) & 255), Double(color & 255)]
    }
  }

  private static let configurations: [String: Configuration] = [
    "neon_overdrive": Configuration(
      controls: ["Intensity", "Glow", "Beam Width", "Lasers"],
      ranges: [0.45...1.55, 0.25...1.45, 0.65...1.35, 0...1.35],
      modes: ["default": [0,1,1.16,1.06,1,0.92], "ambient": [3,0.46,0.72,0.62,1.08,0.35],
              "vivid": [0,1.22,1.38,1.28,1.06,1.2], "minimal": [1,0.68,0.78,0.58,0.86,0.18]],
      nonReactiveModes: [],
      palettes: [[0x02020A,0x00E7FF,0xFF2BD6,0xB9FF32,0xFFB21A],
                 [0x03010B,0x53E8FF,0x7657FF,0xFF31B8,0xFFF4D6],
                 [0x090103,0xFF174E,0xFF7417,0xFFEB3B,0x25E6FF],
                 [0x01060B,0x00D9FF,0x246BFF,0x4CFFD5,0xF4FFFF]],
      paletteSeconds: 0.36,
      envelope: [(0.05,0.34),(0.10,0.46),(0.035,0.18),(0.12,0.52),(0.20,0.74),(0.08,0.38)],
      energyIntensity: 0.72, flowMix: (0.72,0.28), flowUsesBody: true, beatSeconds: 0.12,
      speed: [0.52,0.28,0.22,0.10,0.38], motionRange: 0.35...1.65, overlay: false),
    "prismatic_sanctuary": Configuration(
      controls: ["Intensity", "Glow", "Framing", "Sparkle"],
      ranges: [0.4...1.5,0.2...1.35,0.55...1.5,0...1.25],
      modes: ["default": [0,1,1.14,1.12,1.02,0.9], "ambient": [2,0.38,0.7,0.62,1.18,0.42],
              "vivid": [0,1.18,1.3,1.12,1.08,1.02], "cinematic": [1,0.52,0.88,1,0.82,0.62]],
      nonReactiveModes: [],
      palettes: [[0x02050D,0x25DDFF,0xFF328F,0xFFC857,0xF4FBFF],
                 [0x080604,0xFFE8C4,0xFFA84A,0x9CC9FF,0xFFF7E8],
                 [0x010713,0x53C8FF,0x7568FF,0xC9F5FF,0xDFF7FF],
                 [0x0B0208,0xFF315D,0xFF7A45,0xFFE0A3,0xFFF1DF]],
      paletteSeconds: 0.48,
      envelope: [(0.08,0.44),(0.12,0.56),(0.04,0.24),(0.14,0.58),(0.24,0.82),(0.1,0.48)],
      energyIntensity: 0.7, flowMix: (0.72,0.28), flowUsesBody: true, beatSeconds: 0.2,
      speed: [1.15,0.2,0.06,0,0], motionRange: 0.2...1.7, overlay: false),
    "chladni_resonance": Configuration(
      controls: ["Intensity", "Complexity", "Sand Width"], ranges: [0.45...1.5,2...8,0.45...1.65],
      modes: ["default": [0,1,1,5,1], "ambient": [3,0.42,0.72,3.4,0.78],
              "vivid": [1,1.24,1.28,6.2,1.18], "minimal": [0,0.3,0.62,2.6,0.64]],
      nonReactiveModes: ["minimal"],
      palettes: [[0x050713,0x010207,0x00E7FF,0xFFE866,0xFF2EA6],
                 [0x040916,0x010308,0x4B7BFF,0x43FFB5,0xFF45D7],
                 [0x12060C,0x030103,0xFF315D,0xFFF06A,0x7A5CFF],
                 [0x03110F,0x010302,0x00F0C8,0xFFD84A,0xFF3D8D]],
      paletteSeconds: 0.44,
      envelope: [(0.07,0.38),(0.1,0.46),(0.04,0.2),(0.13,0.5),(0.22,0.76),(0.1,0.42)],
      energyIntensity: 0.68, flowMix: (0.76,0.24), flowUsesBody: true, beatSeconds: 0.18,
      speed: [0.52,0.2,0.06,0,0], motionRange: 0.2...1.8, overlay: false),
    "prismatic_tides": Configuration(
      controls: ["Intensity", "Wave Height", "Choppiness", "Sky Glow"],
      ranges: [0.45...1.55,0.25...1.5,0.2...1.45,0.2...1.5],
      modes: ["default": [0,1,1.08,1.08,1.06,1.06], "ambient": [3,0.44,0.72,0.5,0.42,0.68],
              "vivid": [1,1.16,1.26,1.16,1.12,1.24], "storm": [2,1.32,1.12,1.34,1.3,1.06]],
      nonReactiveModes: [],
      palettes: [[0x010416,0xFF2D95,0x010C26,0x18E7FF,0xFFB21C],
                 [0x16091F,0xFF5C87,0x071B2A,0x58E8CF,0xFFE37A],
                 [0x0B0616,0xFF3B30,0x101A38,0xFFD43B,0x83F5FF],
                 [0x01040E,0x416CFF,0x020D1D,0xC8F6FF,0xF1F5FF]],
      paletteSeconds: 0.46,
      envelope: [(0.075,0.46),(0.11,0.48),(0.04,0.2),(0.14,0.54),(0.2,0.76)],
      energyIntensity: 0.7, flowMix: (0.78,0.22), flowUsesBody: false, beatSeconds: 0.2,
      speed: [0.24,0.36,0,0,0.055], motionRange: 0.25...1.7, overlay: false),
    "event_horizon": Configuration(
      controls: ["Intensity", "Scale", "Turbulence", "Stars"],
      ranges: [0.45...1.55,0.72...1.35,0.25...1.5,0...1.25],
      modes: ["default": [0,1,1,1,0.88,0.72], "ambient": [2,0.46,0.72,0.9,0.52,0.9],
              "vivid": [1,1.18,1.3,1.12,1.24,1.02], "minimal": [3,0.38,0.7,0.84,0.34,0.28]],
      nonReactiveModes: ["minimal"],
      palettes: [[0x010106,0x160B38,0xFFC23A,0xFF236D,0x62ECFF],
                 [0x050108,0x2C0B46,0xFF55D5,0x765CFF,0x62FFE5],
                 [0x01030B,0x092453,0x53A4FF,0x35F5D0,0xFFF1C4],
                 [0x080100,0x3B0B0B,0xFFE143,0xFF3B19,0xB67CFF]],
      paletteSeconds: 0.42,
      envelope: [(0.065,0.42),(0.1,0.46),(0.04,0.2),(0.13,0.52),(0.2,0.78)],
      energyIntensity: 0.7, flowMix: (0.78,0.22), flowUsesBody: false, beatSeconds: 0.2,
      speed: [0.18,0.38,0,0,0.08], motionRange: 0.25...1.65, overlay: false),
    "chromatic_silk": Configuration(
      controls: ["Intensity", "Fold Scale", "Depth", "Gloss", "Texture"],
      ranges: [0.45...1.5,0.35...1.5,0.3...1.55,0.25...1.65,0...1],
      modes: ["default": [0,1,1,0.86,0.92,1,0.32], "ambient": [3,0.46,0.72,0.64,0.68,0.66,0.14],
              "vivid": [1,1.16,1.28,1.08,1.22,1.34,0.48], "minimal": [2,0.38,0.66,0.46,0.54,0.5,0]],
      nonReactiveModes: ["minimal"],
      palettes: [[0x03050D,0x17133E,0x00DDF2,0xFF318B,0xFFF0B8],
                 [0x090512,0x3A1559,0xFF4EC8,0x54FFD0,0xFFE36D],
                 [0x10040A,0x4B1429,0xFF453A,0xFFC832,0x9E7CFF],
                 [0x020910,0x073B59,0x00BFFF,0x36F5A8,0xFFF4DB]],
      paletteSeconds: 0.48,
      envelope: [(0.075,0.44),(0.11,0.48),(0.045,0.22),(0.15,0.56),(0.22,0.82)],
      energyIntensity: 0.68, flowMix: (0.86,0.14), flowUsesBody: false, beatSeconds: 0.22,
      speed: [0.115,0.22,0,0,0.04], motionRange: 0.25...1.7, overlay: false),
    "luminous_matter": Configuration(
      controls: ["Intensity", "Density", "Ray Length", "Texture"],
      ranges: [0.45...1.55,0.35...1.55,0.2...1.5,0...1.25],
      modes: ["default": [0,1,1,1,0.82,0.48], "ambient": [2,0.48,0.78,0.82,0.54,0.18],
              "vivid": [1,1.18,1.28,1.22,1.14,0.82], "minimal": [3,0.62,0.72,0.58,0.38,0]],
      nonReactiveModes: ["minimal"],
      palettes: [[0x02030A,0x28145F,0xFF2488,0x00E6D2,0xFFD52E],
                 [0x08010F,0x5B0FA8,0xFF168F,0x00CFFF,0xF4FF54],
                 [0x03100B,0x124C63,0xFF493F,0x00F0A8,0xFFE02F],
                 [0x020713,0x173E9E,0x00CFFF,0xFF3268,0xFFF04A]],
      paletteSeconds: 0.42,
      envelope: [(0.055,0.36),(0.085,0.31),(0.045,0.20),(0.12,0.48),(0.18,0.72)],
      energyIntensity: 0.72, flowMix: (0.82,0.18), flowUsesBody: false, beatSeconds: 0.24,
      speed: [0.19,0,0,0,0.10], motionRange: 0.25...1.65, overlay: false),
    "spectral_haze": Configuration(
      controls: ["Presence", "Density", "Softness"], ranges: [0.2...1.45,0.2...1.4,0.25...1.5],
      modes: ["default": [0,1,1,0.92,0.88], "subtle": [3,0.48,0.42,0.45,1.2],
              "cinematic": [2,0.7,1.02,0.88,1.1], "vivid": [1,1.18,1.18,1.06,0.64]],
      nonReactiveModes: [],
      palettes: [[0xD9F8FF,0x6C7CFF,0xFFB8E6],[0xFF72D5,0x62EFFF,0xB997FF],
                 [0xFFE4A1,0xFF7658,0x9BDFFF],[0xF1F7FF,0x78A7FF,0x9FFFE8]],
      paletteSeconds: 0.48,
      envelope: [(0.09,0.5),(0.12,0.54),(0.045,0.24),(0.16,0.62),(0.24,0.86)],
      energyIntensity: 0.68, flowMix: (0.86,0.14), flowUsesBody: false, beatSeconds: 0.24,
      speed: [0.09,0.46,0,0.14,0], motionRange: 0.25...1.7, overlay: true),
    "prismatic_lens": Configuration(
      controls: ["Intensity", "Bloom", "Spectrum"], ranges: [0.2...1.45,0.2...1.5,0...1.35],
      modes: ["default": [0,1,0.9,0.76,0.84], "subtle": [3,0.48,0.38,0.48,0.28],
              "cinematic": [2,0.72,0.92,1.08,0.52], "prism": [1,1.18,1.16,0.94,1.24]],
      nonReactiveModes: [],
      palettes: [[0xFFC85B,0xFF4F8E,0x67EFFF],[0xFF5BD8,0x8D6CFF,0x69FFD7],
                 [0x78F3FF,0x4F8CFF,0xFFF0CF],[0xFFE8C1,0xFFB85A,0xB7D5FF]],
      paletteSeconds: 0.42,
      envelope: [(0.075,0.44),(0.11,0.46),(0.04,0.2),(0.14,0.52),(0.22,0.78)],
      energyIntensity: 0.7, flowMix: (0.82,0.18), flowUsesBody: false, beatSeconds: 0.2,
      speed: [0.11,0.3,0,0,0], motionRange: 0.25...1.7, overlay: true),
  ]
}
