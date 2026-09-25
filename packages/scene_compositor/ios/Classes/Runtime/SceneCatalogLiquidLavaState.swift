import Foundation
import CoreGraphics

/// The existing compositor supplies the 60 Hz clock and complete audio authority.
final class SceneCatalogLiquidLavaState {
  private let intensity: Double
  private let motion: Double
  private let density: Double
  private let glow: Double
  private let bubblesEnabled: Bool
  private let causticsEnabled: Bool
  private let dustEnabled: Bool
  private var playing = false
  private var elapsedMicros: Int64 = 0
  private var lastFrameMicros: Int64?
  private var paletteIndex = 0
  private var lastPaletteShiftMicros: Int64 = 0
  private var signal: SceneRenderSignalFrameV2?

  init?(options: [String: Any], mode: String?) {
    let allowed: Set<String> = ["Intensity", "Motion", "Density", "Glow", "Bubbles", "Caustics", "Dust"]
    guard Set(options.keys).isSubset(of: allowed) else { return nil }
    let defaults: (Double, Double, Double, Double, Bool, Bool)
    switch mode {
    case nil, "default": defaults = (1, 1, 0.92, 1, true, true)
    case "sleep": defaults = (0.62, 0.42, 0.7, 0.72, false, false)
    case "vivid": defaults = (1.36, 1.22, 1.08, 1.28, true, true)
    case "cosmic": defaults = (1.18, 0.86, 1.22, 1.45, true, true)
    default: return nil
    }
    func number(_ key: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Double? {
      guard let raw = options[key] else { return fallback }
      guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
        value.doubleValue.isFinite, range.contains(value.doubleValue) else { return nil }
      return value.doubleValue
    }
    func boolean(_ key: String, _ fallback: Bool) -> Bool? {
      guard let raw = options[key] else { return fallback }
      guard let value = raw as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
      return value.boolValue
    }
    guard let intensity = number("Intensity", defaults.0, 0.4...1.75),
      let motion = number("Motion", defaults.1, 0.25...1.75),
      let density = number("Density", defaults.2, 0.45...1.35),
      let glow = number("Glow", defaults.3, 0.35...1.65),
      let bubbles = boolean("Bubbles", true),
      let caustics = boolean("Caustics", defaults.4),
      let dust = boolean("Dust", defaults.5) else { return nil }
    self.intensity = intensity; self.motion = motion; self.density = density; self.glow = glow
    bubblesEnabled = bubbles; causticsEnabled = caustics; dustEnabled = dust
  }

  @discardableResult
  func consume(_ frame: SceneRenderSignalFrameV2) -> Bool {
    guard playing, signal != frame, frame.channels.count == 4,
      frame.dynamics.count == 6, frame.spectrumSummary.count == 7 else { return false }
    signal = frame
    let flash = frame.flash
    if frame.available && frame.musicActive && flash.active &&
      flash.timestampMicros > lastPaletteShiftMicros &&
      flash.timestampMicros - lastPaletteShiftMicros > 1_800_000 {
      lastPaletteShiftMicros = flash.timestampMicros
      paletteIndex = (paletteIndex + 1) % 4
    }
    return true
  }

  func inheritAnimation(from previous: SceneCatalogLiquidLavaState) {
    playing = previous.playing
    elapsedMicros = previous.elapsedMicros
    lastFrameMicros = previous.lastFrameMicros
    paletteIndex = previous.paletteIndex
    lastPaletteShiftMicros = previous.lastPaletteShiftMicros
    signal = previous.signal
  }

  func setPlaying(_ value: Bool, hostTime: Double) {
    guard value != playing else { return }
    playing = value
    lastFrameMicros = nil
    if !value { signal = nil }
  }

  func frame(size: CGSize, hostTime: Double) -> SceneCatalogLiquidLavaFrame {
    if playing, hostTime.isFinite, hostTime >= 0, hostTime < Double(Int64.max / 1_000_000) {
      let now = Int64((hostTime * 1_000_000).rounded())
      if let previous = lastFrameMicros, now > previous {
        elapsedMicros = (elapsedMicros + (now - previous) % 22_000_000) % 22_000_000
      }
      lastFrameMicros = now
    }
    let audio = playing && signal?.available == true && signal?.musicActive == true ? signal : nil
    func summary(_ index: Int) -> Double { audio.map { Double($0.spectrumSummary[index]) } ?? 0 }
    return SceneCatalogLiquidLavaFrame(logicalWidth: size.width, logicalHeight: size.height,
      time: Double(elapsedMicros) / 22_000_000, paletteIndex: paletteIndex,
      intensity: intensity, motion: motion, density: density, glow: glow,
      bubblesEnabled: bubblesEnabled, causticsEnabled: causticsEnabled, dustEnabled: dustEnabled,
      subBass: summary(0), bass: audio.map { Double($0.channels[0]) } ?? 0,
      lowMid: summary(2), mid: summary(3), highMid: summary(4), treble: summary(5), air: summary(6),
      energy: audio.map { Double($0.dynamics[1]) } ?? 0,
      brightness: audio.map { Double($0.dynamics[4]) } ?? 0,
      accentStrength: audio.map { Double($0.accent.strength) } ?? 0,
      flashStrength: audio.map { Double($0.flash.strength) } ?? 0)
  }
}
