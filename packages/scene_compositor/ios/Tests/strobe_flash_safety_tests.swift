import CoreGraphics
import Foundation

// Compiled by check_strobe_flash_safety.py with the production strobe types
// nested in StrobeHarness; `schemaVelocityByMode` is prepended from the Dart
// t_bw schema. A flash is one on/off cycle, i.e. two visible changes: at most
// three flashes means at most six changes in any one-second window.

typealias H = StrobeHarness

var failures = 0

func expect(_ condition: Bool, _ message: String) {
  if condition { return }
  failures += 1
  print("FAIL \(message)")
}

func options(
  _ program: H.StrobeProgram, mode: String? = nil, _ raw: [String: Any]? = nil
) -> H.StrobeOptions {
  var parameters: [String: Any] = [
    "programId": program.rawValue, "audioReactive": program.audioReactive,
  ]
  if let mode { parameters["mode"] = mode }
  if let raw { parameters["options"] = raw }
  guard let parsed = H.strobeOptions(parameters, program: program) else {
    fatalError("strobe parameters rejected: \(parameters)")
  }
  return parsed
}

struct Measurement {
  let changesPerSecond: Double
  let worstWindowChanges: Int
}

/// Plays the strobe like the renderer does (advance by each frame's delta)
/// and counts every visible change of the published frame.
func measure(
  _ program: H.StrobeProgram, _ strobeOptions: H.StrobeOptions,
  frames: [Int64] = [16_667], seconds: Int64 = 12
) -> Measurement {
  let state = H.StrobeState(
    layer: H.StrobeLayer(
      id: "probe", program: program, opacity: 1, options: strobeOptions),
    playing: true)
  var now: Int64 = 0
  var index = 0
  var last = state.frame
  var changes = [Int64]()
  while now < seconds * 1_000_000 {
    let delta = frames[index % frames.count]
    index += 1
    now += delta
    _ = state.advance(by: delta)
    if state.frame != last {
      changes.append(now)
      last = state.frame
    }
  }
  var worst = 0
  var start = 0
  for end in changes.indices {
    while changes[end] - changes[start] >= 1_000_000 { start += 1 }
    worst = max(worst, end - start + 1)
  }
  return Measurement(
    changesPerSecond: Double(changes.count) / Double(seconds),
    worstWindowChanges: worst)
}

func report(_ name: String, _ m: Measurement) {
  let flashes = String(format: "%.2f", m.changesPerSecond / 2)
  print("\(name): \(flashes) flashes/s, worst 1 s window \(m.worstWindowChanges) changes")
  expect(
    m.worstWindowChanges <= 6,
    "\(name) shows \(m.worstWindowChanges) changes in one second (max 6 = 3 flashes)")
}

// Late and uneven frames (thermal brake, dropped frames) never let a fourth
// flash into a window.
let unevenFrames: [Int64] = [8_333, 16_667, 33_333, 50_000, 16_667, 120_000, 4_000]

report("Colorful Illumination (b_colorlights default) 60 Hz",
  measure(.backgroundColorLights, options(.backgroundColorLights)))
report("Colorful Illumination uneven frames",
  measure(.backgroundColorLights, options(.backgroundColorLights), frames: unevenFrames))
report("Colorful Illumination remote Velocity 1000 without black",
  measure(.backgroundColorLights, options(.backgroundColorLights, [
    "Velocity": 1_000, "Show Black Screen": false,
  ])))
report("Black & White background (b_bw default) 60 Hz",
  measure(.backgroundBlackWhite, options(.backgroundBlackWhite)))

// Dance Dance renders t_bw in its default mode; the editor materialises the
// schema values of that mode into the stored options.
for mode in ["default", "fast", "slow", "rainbow", "bright rainbow"] {
  guard let velocity = schemaVelocityByMode[mode] else {
    expect(false, "schema has no t_bw mode \(mode)")
    continue
  }
  let stored = options(.transparentBlackWhite, mode: mode == "default" ? "" : mode, [
    "Velocity": velocity, "Smooth Transitions": false,
  ])
  let authored = options(.transparentBlackWhite, mode: mode == "default" ? "" : mode)
  expect(
    stored.intervalMicros == authored.intervalMicros,
    "t_bw \(mode): stored Velocity \(velocity) plays a \(stored.intervalMicros ?? 0) µs phase, "
      + "the mode itself \(authored.intervalMicros ?? 0) µs")
  var plain = stored
  plain.smooth = false
  report("t_bw \(mode) (Velocity \(velocity)) 60 Hz", measure(.transparentBlackWhite, plain))
}

/// Music flash events every 50 ms (20 per second), as the renderer plays them:
/// every accepted event is one visible change (a colour swap) and a Pro Strobe
/// flash also turns off `flashDurationSeconds` later. They all share the
/// six-changes-per-second window, like the Dart VisualFlashChangeWindow.
func measureMusic(_ program: H.StrobeProgram, everyMicros: Int64 = 50_000, seconds: Int64 = 6) -> Measurement {
  let state = H.StrobeState(
    layer: H.StrobeLayer(id: "probe", program: program, opacity: 1, options: options(program)),
    playing: true)
  let quiet = SceneRenderSignalEventV2(serial: 0, active: false, timestampMicros: 0, strength: 0, band: .low)
  var changes = [Int64]()
  var hideAt: Int64?
  var serial: Int64 = 0
  var now: Int64 = 0
  while now < seconds * 1_000_000 {
    now += 10_000
    if let at = hideAt, now >= at {
      hideAt = nil
      if state.hideTimedFlash() { changes.append(at) }
    }
    guard now % everyMicros == 0 else { continue }
    serial += 1
    let flash = SceneRenderSignalEventV2(serial: serial, active: true, timestampMicros: now, strength: 1, band: .broadband)
    let signal = SceneRenderSignalFrameV2(sessionId: 1, sequence: serial, audioTimestampMicros: now,
      available: true, fresh: true, musicActive: true, tonalAvailable: false,
      dynamics: [Float](repeating: 0.8, count: 6), channels: [Float](repeating: 0.8, count: 4),
      spectrumSummary: [Float](repeating: 0.6, count: 7), instantSpectrum: [Float](repeating: 0.6, count: 31),
      smoothedSpectrum: [Float](repeating: 0.6, count: 31), semantics: [Float](repeating: 0, count: 6),
      rhythm: [120, 0.5, 0, 0], onsets: [0, 0, 0, 0], tonal: [0, 0, 0],
      impact: quiet, accent: quiet, beat: quiet, flash: flash)
    if state.consume(signal) {
      changes.append(now)
      if program == .transparentProStrobe {
        hideAt = now + Int64((state.flashDurationSeconds * 1_000_000).rounded())
      }
    }
  }
  var worst = 0
  var start = 0
  for end in changes.indices {
    while changes[end] - changes[start] >= 1_000_000 { start += 1 }
    worst = max(worst, end - start + 1)
  }
  return Measurement(
    changesPerSecond: Double(changes.count) / Double(seconds), worstWindowChanges: worst)
}

for program in [H.StrobeProgram.backgroundSimpleDisco, .backgroundProColorful, .transparentProStrobe] {
  let m = measureMusic(program)
  expect(m.changesPerSecond > 0, "\(program.rawValue) never reacted to music flash events")
  report("\(program.rawValue) with music flash events every 50 ms", m)
}

if failures > 0 {
  print("\(failures) strobe flash safety failure(s)")
  exit(1)
}
print("PASS strobe flash simulation")
