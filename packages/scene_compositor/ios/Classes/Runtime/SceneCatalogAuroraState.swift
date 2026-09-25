import Foundation
import CoreGraphics

/// State authority for Aurora's existing Canvas painter. The compositor owns
/// the render clock; this class preserves its fourteen-second VsyncFrameClock cycle.
final class SceneCatalogAuroraState {
  private let intensity: Double
  private let texture: Double
  private let motion: Double
  private let depthEnabled: Bool
  private let particlesEnabled: Bool
  private let spectrumEnabled: Bool
  private var playing = false
  private var elapsedMicros: Int64 = 0
  private var lastFrameMicros: Int64?
  private var paletteIndex = 0
  private var signal: SceneRenderSignalFrameV2?

  init?(options: [String: Any], mode: String?) {
    let allowed: Set<String> = ["Intensity", "Motion", "Texture", "Depth", "Particles", "Spectrum"]
    guard Set(options.keys).isSubset(of: allowed) else { return nil }
    let defaults: (Double, Double, Double, Bool, Bool, Bool)
    switch mode {
    case "ambient": defaults = (0.62, 0.55, 0.45, true, true, false)
    case "vivid": defaults = (1.42, 1.28, 1.05, true, true, true)
    case "minimal": defaults = (0.78, 0.8, 0.25, false, false, false)
    default: defaults = (1, 1, 0.8, true, true, true)
    }
    func number(_ name: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Double? {
      guard let raw = options[name] else { return fallback }
      guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
            value.doubleValue.isFinite, range.contains(value.doubleValue) else { return nil }
      return value.doubleValue
    }
    func boolean(_ name: String, _ fallback: Bool) -> Bool? {
      guard let raw = options[name] else { return fallback }
      guard let value = raw as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID()
      else { return nil }
      return value.boolValue
    }
    guard let intensity = number("Intensity", defaults.0, 0.35...1.75),
          let motion = number("Motion", defaults.1, 0.25...1.85),
          let texture = number("Texture", defaults.2, 0...1.35),
          let depth = boolean("Depth", defaults.3),
          let particles = boolean("Particles", defaults.4),
          let spectrum = boolean("Spectrum", defaults.5) else { return nil }
    self.intensity = intensity
    self.texture = texture
    self.motion = motion
    depthEnabled = depth
    particlesEnabled = particles
    spectrumEnabled = spectrum
  }

  @discardableResult
  func consume(_ frame: SceneRenderSignalFrameV2) -> Bool {
    // The Dart binding stops while paused and supplies forMusicReaction().
    guard playing, signal != frame,
          frame.channels.count == 4, frame.dynamics.count == 6,
          frame.spectrumSummary.count == 7, frame.smoothedSpectrum.count == 31
    else { return false }
    signal = frame
    if frame.available && frame.musicActive && frame.flash.active {
      // Original onFrame increments on active callbacks, not on serial changes.
      paletteIndex = (paletteIndex + 1) % 4
    }
    return true
  }

  func inheritAnimation(from previous: SceneCatalogAuroraState) {
    playing = previous.playing
    elapsedMicros = previous.elapsedMicros
    lastFrameMicros = previous.lastFrameMicros
    paletteIndex = previous.paletteIndex
    signal = previous.signal
  }

  func setPlaying(_ value: Bool, hostTime: Double) {
    guard value != playing else { return }
    playing = value
    // VsyncFrameClock resets its frame timestamp on both stop and start. Its
    // first callback establishes a timestamp without advancing the phase.
    lastFrameMicros = nil
    if !value { signal = nil }
  }

  func frame(size: CGSize, hostTime: Double) -> SceneCatalogAuroraFrame {
    if playing, hostTime.isFinite, hostTime >= 0,
       hostTime < Double(Int64.max / 1_000_000) {
      let now = Int64((hostTime * 1_000_000).rounded())
      if let previous = lastFrameMicros, now > previous {
        // Only the phase is observable. Keeping its exact integer remainder
        // prevents accumulating an unbounded counter over long sessions.
        elapsedMicros = (elapsedMicros + (now - previous) % 14_000_000) % 14_000_000
      }
      lastFrameMicros = now
    }
    let active = playing && signal?.available == true && signal?.musicActive == true
    let audio = active ? signal : nil
    func summary(_ index: Int) -> Double { audio.map { Double($0.spectrumSummary[index]) } ?? 0 }
    return SceneCatalogAuroraFrame(
      logicalWidth: Double(size.width), logicalHeight: Double(size.height),
      time: Double(elapsedMicros) / 14_000_000,
      paletteIndex: paletteIndex, intensity: intensity, motion: motion, texture: texture,
      depthEnabled: depthEnabled, particlesEnabled: particlesEnabled,
      spectrumEnabled: spectrumEnabled,
      subBass: summary(0), bass: audio.map { Double($0.channels[0]) } ?? 0,
      lowMid: summary(2), mid: summary(3), highMid: summary(4),
      treble: summary(5), air: summary(6),
      energy: audio.map { Double($0.dynamics[1]) } ?? 0,
      brightness: audio.map { Double($0.dynamics[4]) } ?? 0,
      accentStrength: audio.map { Double($0.accent.strength) } ?? 0,
      flashStrength: audio.map { Double($0.flash.strength) } ?? 0,
      // VisualRenderFrame.empty has an EMPTY spectrum. Thirty-one zero bins
      // would incorrectly draw Aurora's minimum-height spectrum bars.
      spectrum: audio.map { $0.smoothedSpectrum.map(Double.init) } ?? [])
  }
}
