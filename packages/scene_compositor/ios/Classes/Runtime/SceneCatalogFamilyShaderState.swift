import Foundation
import CoreGraphics

/// State-only ports of ReactiveGpuBackground and RecoveredShaderBackground.
/// The scene compositor owns time and cadence; uniforms follow the Dart painter ABI.
final class SceneCatalogFamilyShaderState {
  private struct Controls {
    var palette: Int
    var intensity: Double
    var motion: Double
    var atmosphere: Double
    var structure: Double
    var accents: Double

    init(_ values: [Double]) {
      palette = Int(values[0]); intensity = values[1]; motion = values[2]
      atmosphere = values[3]; structure = values[4]; accents = values[5]
    }
  }

  private struct Spec {
    let palettes: [[UInt32]]
    let modes: [String: [Double]]
    let labels: [String]
    let recovered: Bool
  }

  private let spec: Spec
  private let controls: Controls
  private let reactive: Bool
  private var displayPalette: [Double]
  private var playing = true
  private var lastHostTime: Double?
  private var visualTime = 0.0
  private var frame: SceneRenderSignalFrameV2?
  private var pendingFlashSteps = 0
  private var pendingFlashStrength = 0.0
  private var pendingFlashAccepted = false
  private var lastQueuedFlash: (session: Int64, serial: Int64)?
  private var bass = 0.0
  private var body = 0.0
  private var spark = 0.0
  private var pulse = 0.0
  private var energy = 0.0
  private var flow = 0.0
  private var rhythm = 0.0
  private var show = 0.0
  private var gate = 0.0
  private var choreography = 0
  private var lastFlashSession: Int64 = 0
  private var lastFlashSerial: Int64 = 0

  init?(program: String, options: [String: Any], mode: String?) {
    guard let spec = Self.specs[program] else { return nil }
    let names = ["Palette", "Intensity", "Motion"] + spec.labels
    let numericKeys = Set(names)
    let authoredRanges: [ClosedRange<Double>] = spec.recovered
      ? [0...Double(spec.palettes.count - 1), 0.4...1.5, 0.2...1.7, 0.2...1.35, 0.55...1.5, 0...1.25]
      : [0...Double(spec.palettes.count - 1), 0.4...1.45, 0.35...1.55, 0...1.35, 0.65...1.35, 0...1.3]
    let limits = Dictionary(uniqueKeysWithValues: names.enumerated().map { index, name in
      let defaults = spec.modes.values.map { $0[index] }
      let lower = min(authoredRanges[index].lowerBound, defaults.min()!)
      let upper = max(authoredRanges[index].upperBound, defaults.max()!)
      return (name, lower...upper)
    })
    let allowed = numericKeys.union(["Music Reactive", "Debug Signal"])
    guard Set(options.keys).isSubset(of: allowed), options.allSatisfy({ key, raw in
      guard let value = raw as? NSNumber else { return false }
      if key == "Music Reactive" { return CFGetTypeID(value) == CFBooleanGetTypeID() }
      guard CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite
      else { return false }
      // Stored development scenes may contain the live signal selection. A
      // synthetic debug signal is not implemented by the production runtime.
      if key == "Debug Signal" { return !spec.recovered && value.doubleValue == 0 }
      guard limits[key]?.contains(value.doubleValue) == true else { return false }
      return key != "Palette" || value.doubleValue.rounded(.towardZero) == value.doubleValue
    }) else { return nil }
    self.spec = spec
    var controls = Controls(spec.modes[mode ?? "default"] ?? spec.modes["default"]!)
    func number(_ name: String, _ fallback: Double) -> Double {
      guard let value = options[name] as? NSNumber,
            CFGetTypeID(value) != CFBooleanGetTypeID(),
            value.doubleValue.isFinite else { return fallback }
      return value.doubleValue
    }
    let palette = number("Palette", Double(controls.palette))
    controls.palette = Int(min(Double(spec.palettes.count - 1), max(0, palette)))
    controls.intensity = number("Intensity", controls.intensity)
    controls.motion = number("Motion", controls.motion)
    controls.atmosphere = number(spec.labels[0], controls.atmosphere)
    controls.structure = number(spec.labels[1], controls.structure)
    controls.accents = number(spec.labels[2], controls.accents)
    self.controls = controls
    reactive = options["Music Reactive"] as? Bool ?? true
    // Flutter initializes the displayed palette before applying modes/options.
    displayPalette = Self.rgb(spec.palettes[0])
  }

  @discardableResult
  func consume(_ next: SceneRenderSignalFrameV2) -> Bool {
    guard next.dynamics.count >= 4, next.channels.count >= 4,
          next.rhythm.count >= 4 else { return false }
    let changed = frame != next
    frame = next
    // VisualAudioBinding.forMusicReaction gates by available/music, not fresh.
    if reactive, !spec.recovered, next.available, next.musicActive,
       next.flash.active, next.flash.serial > 0,
       lastQueuedFlash?.session != next.sessionId || lastQueuedFlash?.serial != next.flash.serial {
      // Coalesce the exact state effect, not the event: bounded storage still
      // retains every choreography step and the strongest unpresented pulse.
      pendingFlashSteps = (pendingFlashSteps + 1) % 4
      pendingFlashStrength = max(pendingFlashStrength, unit(Double(next.flash.strength)))
      pendingFlashAccepted = true
      lastQueuedFlash = (next.sessionId, next.flash.serial)
    }
    return changed
  }

  /// Controls are replaceable without restarting the authored animation.
  func inheritAnimation(from previous: SceneCatalogFamilyShaderState) {
    displayPalette = previous.displayPalette
    playing = previous.playing
    lastHostTime = previous.lastHostTime
    visualTime = previous.visualTime
    frame = previous.frame
    pendingFlashSteps = previous.pendingFlashSteps
    pendingFlashStrength = previous.pendingFlashStrength
    pendingFlashAccepted = previous.pendingFlashAccepted
    lastQueuedFlash = previous.lastQueuedFlash
    bass = previous.bass; body = previous.body; spark = previous.spark
    pulse = previous.pulse; energy = previous.energy; flow = previous.flow
    rhythm = previous.rhythm; show = previous.show; gate = previous.gate
    choreography = previous.choreography
    lastFlashSession = previous.lastFlashSession
    lastFlashSerial = previous.lastFlashSerial
    if !reactive { resetDynamics() }
  }

  func setPlaying(_ next: Bool, hostTime: Double) {
    guard next != playing else { return }
    playing = next
    lastHostTime = hostTime
    if !next { resetDynamics() }
  }

  func uniforms(size: CGSize, hostTime: Double, reducedMotion: Bool) -> [Float] {
    guard size.width > 0, size.height > 0, hostTime.isFinite else { return [] }
    let dt = min(0.05, max(0, lastHostTime.map { hostTime - $0 } ?? 0.016666))
    lastHostTime = hostTime
    if playing {
      update(delta: dt)
      let speed = spec.recovered
        ? 1.15 * (1 + flow * 0.2 + rhythm * 0.06)
        : 0.62 + flow * 0.10 + rhythm * 0.035
      visualTime += dt * controls.motion * speed
      let blend = 1 - exp(-dt / (spec.recovered ? 0.48 : 0.34))
      let target = Self.rgb(spec.palettes[controls.palette])
      for index in displayPalette.indices {
        displayPalette[index] += (target[index] - displayPalette[index]) * blend
      }
    } else {
      resetDynamics()
    }
    // Neither original family alters uniforms for Reduce Motion. Cadence and
    // lifecycle remain the host's responsibility; do not invent motion scaling.
    var values = [Double(size.width), Double(size.height), visualTime,
                  bass, body, spark, pulse, energy, flow, rhythm]
    if spec.recovered {
      values += [controls.intensity, controls.atmosphere, controls.structure,
                 controls.accents, reactive ? 1 : 0]
    } else {
      values += [Double(choreography), show, controls.intensity, controls.motion,
                 controls.atmosphere, controls.structure, controls.accents,
                 reactive ? gate : 0]
    }
    // Color.lerp keeps continuous color state; Dart toARGB32 rounds only at upload.
    values += displayPalette.map { min(255, max(0, ($0 * 255).rounded())) / 255 }
    return values.map(Float.init)
  }

  private func update(delta dt: Double) {
    let input = reactive && frame?.available == true && frame?.musicActive == true ? frame : nil
    func channel(_ index: Int) -> Double { input.map { Double($0.channels[index]) } ?? 0 }
    func dynamic(_ index: Int) -> Double { input.map { Double($0.dynamics[index]) } ?? 0 }
    let groove = input.map { Double($0.rhythm[3]) } ?? 0
    let impact = input.map { Double($0.impact.strength) } ?? 0
    if spec.recovered {
      bass = follow(bass, channel(0), dt, 0.08, 0.44)
      body = follow(body, channel(1), dt, 0.12, 0.56)
      spark = follow(spark, channel(2), dt, 0.04, 0.24)
      energy = follow(energy, max(dynamic(3), dynamic(2) * 0.7), dt, 0.14, 0.58)
      flow = follow(flow, channel(3) * 0.72 + channel(1) * 0.28, dt, 0.24, 0.82)
      rhythm = follow(rhythm, groove, dt, 0.1, 0.48)
      let flash = input.map { Double($0.flash.strength) } ?? 0
      pulse = max(unit(max(impact, flash)), pulse * exp(-dt / 0.2))
    } else {
      bass = follow(bass, channel(0), dt, 0.055, 0.38)
      body = follow(body, channel(1), dt, 0.11, 0.52)
      spark = follow(spark, channel(2), dt, 0.035, 0.20)
      energy = follow(energy, dynamic(3), dt, 0.13, 0.58)
      flow = follow(flow, channel(3) * 0.68 + channel(1) * 0.32, dt, 0.22, 0.82)
      rhythm = follow(rhythm, max(groove, input.map { Double($0.beat.strength) } ?? 0), dt, 0.09, 0.44)
      pulse *= exp(-dt / 0.105)
      var accepted = pendingFlashAccepted
      if pendingFlashAccepted, let queued = lastQueuedFlash {
        lastFlashSession = queued.session; lastFlashSerial = queued.serial
        choreography = (choreography + pendingFlashSteps) % 4
        pulse = max(pulse, sqrt(pendingFlashStrength))
      }
      pendingFlashAccepted = false; pendingFlashSteps = 0; pendingFlashStrength = 0
      if let input, input.flash.active, input.flash.serial > 0,
         input.sessionId != lastFlashSession || input.flash.serial != lastFlashSerial {
        lastFlashSession = input.sessionId; lastFlashSerial = input.flash.serial
        lastQueuedFlash = (input.sessionId, input.flash.serial)
        choreography = (choreography + 1) % 4
        pulse = max(pulse, sqrt(unit(Double(input.flash.strength))))
        accepted = true
      }
      if !accepted { pulse = max(pulse, impact * 0.24) }
      let reactionGate = input == nil ? 0.0 : 1.0
      show = follow(show, (energy * 0.50 + rhythm * 0.28 + bass * 0.22) * reactionGate, dt, 0.16, 0.66)
      gate = follow(gate, reactionGate, dt, 0.08, 0.42)
    }
  }

  private func resetDynamics() {
    bass = 0; body = 0; spark = 0; pulse = 0; energy = 0; flow = 0
    rhythm = 0; show = 0; gate = 0; choreography = 0
    lastFlashSession = 0; lastFlashSerial = 0
    pendingFlashSteps = 0; pendingFlashStrength = 0; pendingFlashAccepted = false
    lastQueuedFlash = nil
  }

  private func unit(_ value: Double) -> Double { min(1, max(0, value)) }
  private func follow(_ current: Double, _ target: Double, _ dt: Double,
                      _ attack: Double, _ release: Double) -> Double {
    let target = unit(target)
    return current + (target - current) * (1 - exp(-dt / (target > current ? attack : release)))
  }

  private static func rgb(_ palette: [UInt32]) -> [Double] {
    palette.flatMap { value in [Double((value >> 16) & 255) / 255,
                               Double((value >> 8) & 255) / 255, Double(value & 255) / 255] }
  }

  private static let specs: [String: Spec] = {
    var result: [String: Spec] = [:]
    func reactive(_ name: String, _ palettes: [[UInt32]], _ modes: [[Double]], _ labels: [String]) {
      result[name] = Spec(palettes: palettes, modes: Dictionary(uniqueKeysWithValues:
        zip(["default", "ambient", "vivid", "minimal"], modes)), labels: labels, recovered: false)
    }
    reactive("neon_arena", [
      [0x02040A, 0x18DDF2, 0xFF2AA5, 0xB9FF3E, 0xFFBE55],
      [0x04020C, 0x5EE7FF, 0x8B5CFF, 0xFF3CC7, 0xFFE4A3],
      [0x080205, 0xFF315B, 0xFF703D, 0xFFD34E, 0x68F4FF],
      [0x01070C, 0x10D8FF, 0x3977FF, 0x46FFD1, 0xE9FCFF]], [
      [0, 1.02, 0.92, 0.82, 1, 0.72], [3, 0.70, 0.52, 0.92, 1.08, 0.12],
      [0, 1.28, 1.16, 1.04, 1.05, 1.08], [1, 0.72, 0.66, 0.48, 0.86, 0]],
      ["Haze", "Beam Spread", "Laser Accents"])
    reactive("infinity_circuit", [
      [0x02030B, 0x23E7FF, 0xFF2BB7, 0x9DFF43, 0xFFD166],
      [0x09030C, 0xFF5D7D, 0x855CFF, 0xFFB547, 0xFFF0CB],
      [0x01070B, 0x3EEAFF, 0x3D78FF, 0x55FFD0, 0xF2FFFF],
      [0x080102, 0xFF244E, 0xFF6A22, 0xFFD629, 0x4DEBFF]], [
      [0, 1.02, 1, 0.58, 1, 0.76], [2, 0.70, 0.54, 0.78, 1.12, 0.22],
      [0, 1.30, 1.24, 0.72, 0.92, 1.10], [1, 0.74, 0.72, 0.28, 1.16, 0.06]],
      ["Depth Haze", "Tunnel Width", "Edge Traces"])
    reactive("electric_topography", [
      [0x02050A, 0x12E4FF, 0x8D62FF, 0xFF3F9F, 0xB5FF57],
      [0x090403, 0xFFB43B, 0xFF4D73, 0xAE63FF, 0xFFF0B3],
      [0x01070B, 0x5DF2FF, 0x367CFF, 0x43FFD0, 0xE9FFFF],
      [0x06020A, 0xB15CFF, 0xFF3EC8, 0x39DFFF, 0xFFCF5B]], [
      [0, 0.98, 0.88, 0.62, 1, 0.66], [2, 0.68, 0.48, 0.82, 1.12, 0.22],
      [3, 1.24, 1.12, 0.72, 0.92, 1.04], [1, 0.72, 0.62, 0.34, 1.20, 0.08]],
      ["Horizon Haze", "Terrain Scale", "Crest Glow"])
    reactive("crystal_reactor", [
      [0x03040A, 0x67ECFF, 0xFF62C8, 0x8B72FF, 0xFFE69D],
      [0x010806, 0x37FFD1, 0x19BFFF, 0xB7FF43, 0xF1FFF5],
      [0x090402, 0xFFC044, 0xFF5A49, 0xFFED85, 0x69ECFF],
      [0x080205, 0xFF315F, 0x4EDBFF, 0xFF73D5, 0xF4FDFF]], [
      [0, 1, 0.82, 0.64, 1, 0.72], [1, 0.68, 0.46, 0.82, 1.10, 0.18],
      [3, 1.26, 1.08, 0.76, 0.94, 1.08], [2, 0.72, 0.58, 0.30, 1.18, 0.06]],
      ["Chamber Haze", "Crystal Scale", "Facet Glints"])
    reactive("neon_metropolis", [
      [0x02050A, 0x28DFFF, 0xFF3A9F, 0x8D65FF, 0xFFC45E],
      [0x080305, 0xFF637C, 0x7D63FF, 0xFFB347, 0xFFF0C7],
      [0x070502, 0xFFC34B, 0xFF6A3C, 0x3DDCF2, 0xFFF1B0],
      [0x01070B, 0x46E9FF, 0x477DFF, 0x47FFD0, 0xE9FCFF]], [
      [0, 0.94, 0.72, 0.78, 1, 0.54], [3, 0.66, 0.42, 0.96, 1.08, 0.16],
      [0, 1.18, 0.94, 0.88, 0.94, 0.88], [2, 0.70, 0.54, 0.44, 1.16, 0.04]],
      ["City Haze", "Street Depth", "Window Glow"])
    reactive("luminous_falls", [
      [0x02070A, 0x2EE9E0, 0x7B68FF, 0xFF50B8, 0xFFD46A],
      [0x090304, 0xFF6B82, 0xFFA34A, 0x9B63FF, 0xFFF0CB],
      [0x080602, 0xFFCE59, 0xFF7242, 0x46DBE8, 0xFFF6C7],
      [0x01070B, 0x59E8FF, 0x5379FF, 0x4AFFCB, 0xF0FFFF]], [
      [0, 0.96, 0.80, 0.74, 1, 0.64], [3, 0.66, 0.44, 0.92, 1.12, 0.14],
      [1, 1.20, 1.02, 0.86, 0.94, 0.96], [2, 0.70, 0.56, 0.38, 1.18, 0.04]],
      ["Mist", "Fall Width", "Water Glints"])
    let recovered = Spec(palettes: [
      [0x02050D, 0x25DDFF, 0xFF328F, 0xFFC857, 0xF4FBFF],
      [0x080604, 0xFFE8C4, 0xFFA84A, 0x9CC9FF, 0xFFF7E8],
      [0x010713, 0x53C8FF, 0x7568FF, 0xC9F5FF, 0xDFF7FF],
      [0x0B0208, 0xFF315D, 0xFF7A45, 0xFFE0A3, 0xFFF1DF]], modes: [
      "default": [0, 1.14, 1, 1.12, 1.02, 0.9],
      "ambient": [2, 0.7, 0.38, 0.62, 1.18, 0.42],
      "vivid": [0, 1.3, 1.18, 1.12, 1.08, 1.02],
      "cinematic": [1, 0.88, 0.52, 1, 0.82, 0.62]],
      labels: ["Atmosphere", "Structure", "Texture"], recovered: true)
    for index in 1...4 { result[String(format: "velvet_stage_%02d", index)] = recovered }
    for index in 1...5 { result[String(format: "prismatic_caustics_%02d", index)] = recovered }
    result["kaleidoscope_runway"] = recovered
    return result
  }()
}
