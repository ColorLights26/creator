import CoreGraphics
import Foundation

// Compiled by check_strobe_flash_safety.py with the production strobe types
// nested in StrobeHarness; `schemaVelocityByMode` is prepended from the Dart
// t_bw schema. A flash is one on/off cycle, i.e. two visible changes: at most
// three flashes means at most six changes in any one-second window.
//
// The limiter is a scene option (06-nov-2026): OFF by default, strobes play at
// their original speed; ON (`limitFlashes`), they keep the ceiling above.

typealias H = StrobeHarness

var failures = 0

func expect(_ condition: Bool, _ message: String) {
  if condition { return }
  failures += 1
  print("FAIL \(message)")
}

func options(
  _ program: H.StrobeProgram, mode: String? = nil, _ raw: [String: Any]? = nil,
  limit: Bool = false
) -> H.StrobeOptions {
  var parameters: [String: Any] = [
    "programId": program.rawValue, "audioReactive": program.audioReactive,
  ]
  if let mode { parameters["mode"] = mode }
  if let raw { parameters["options"] = raw }
  guard var parsed = H.strobeOptions(parameters, program: program) else {
    fatalError("strobe parameters rejected: \(parameters)")
  }
  expect(!parsed.limitFlashes, "\(program.rawValue): a document turned the flash limit on")
  parsed.limitFlashes = limit
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

/// OFF (the default) plays exactly the phase the program, mode or Velocity
/// asks for, as before the limiter: one change per phase, or one every two
/// phases where the palette repeats the off colour (b_bw: white, black).
func reportOriginal(_ name: String, _ program: H.StrobeProgram, _ original: H.StrobeOptions,
                    authoredMicros: Int64, changesPerPhase: Double = 1) {
  expect(original.intervalMicros == authoredMicros,
    "\(name): plays a \(original.intervalMicros ?? 0) µs phase without the limit, "
      + "authored \(authoredMicros) µs")
  let m = measure(program, original)
  let expected = changesPerPhase * 1_000_000.0 / Double(authoredMicros)
  print("\(name) without the limit: \(String(format: "%.2f", m.changesPerSecond / 2)) flashes/s")
  expect(abs(m.changesPerSecond - expected) <= expected * 0.05,
    "\(name): \(m.changesPerSecond) changes/s without the limit, original speed is \(expected)")
}

/// The graph cadence: the program's own clock without the limit (as before
/// it), the capped phase with it.
func expectCadence(_ name: String, _ program: H.StrobeProgram, _ strobeOptions: H.StrobeOptions) {
  let layer = H.StrobeLayer(id: "probe", program: program, opacity: 1, options: strobeOptions)
  let expected = strobeOptions.limitFlashes
    ? strobeOptions.intervalMicros : program.logicalIntervalMicros
  expect(layer.cadenceIntervalMicros == expected,
    "\(name): graph cadence \(layer.cadenceIntervalMicros ?? 0) µs, expected \(expected ?? 0) µs")
}

// Late and uneven frames (thermal brake, dropped frames) never let a fourth
// flash into a window.
let unevenFrames: [Int64] = [8_333, 16_667, 33_333, 50_000, 16_667, 120_000, 4_000]

reportOriginal("Colorful Illumination (b_colorlights default) 60 Hz", .backgroundColorLights,
  options(.backgroundColorLights), authoredMicros: 50_000)
reportOriginal("Black & White background (b_bw default) 60 Hz", .backgroundBlackWhite,
  options(.backgroundBlackWhite), authoredMicros: 50_000, changesPerPhase: 0.5)
expect(options(.backgroundColorLights, ["Velocity": 1_000, "Show Black Screen": false])
  .intervalMicros == 6_000, "Colorful Illumination Velocity 1000 without the limit is not its 6 ms phase")
for program in [H.StrobeProgram.backgroundColorLights, .backgroundBlackWhite, .transparentBlackWhite] {
  expectCadence("\(program.rawValue) without the limit", program, options(program))
  expectCadence("\(program.rawValue) with the limit", program, options(program, limit: true))
}

report("Colorful Illumination (b_colorlights default) 60 Hz, limited",
  measure(.backgroundColorLights, options(.backgroundColorLights, limit: true)))
report("Colorful Illumination uneven frames, limited",
  measure(.backgroundColorLights, options(.backgroundColorLights, limit: true), frames: unevenFrames))
report("Colorful Illumination remote Velocity 1000 without black, limited",
  measure(.backgroundColorLights, options(.backgroundColorLights, [
    "Velocity": 1_000, "Show Black Screen": false,
  ], limit: true)))
report("Black & White background (b_bw default) 60 Hz, limited",
  measure(.backgroundBlackWhite, options(.backgroundBlackWhite, limit: true)))

// Dance Dance renders t_bw in its default mode; the editor materialises the
// schema values of that mode into the stored options. The Velocity scale is
// the same with or without the limit.
let tbwModePhaseMicros: [String: Int64] = [
  "default": 50_000, "fast": 50_000, "slow": 500_000, "rainbow": 100_000, "bright rainbow": 100_000,
]
for mode in ["default", "fast", "slow", "rainbow", "bright rainbow"] {
  guard let velocity = schemaVelocityByMode[mode] else {
    expect(false, "schema has no t_bw mode \(mode)")
    continue
  }
  for limit in [false, true] {
    let stored = options(.transparentBlackWhite, mode: mode == "default" ? "" : mode, [
      "Velocity": velocity, "Smooth Transitions": false,
    ], limit: limit)
    let authored = options(.transparentBlackWhite, mode: mode == "default" ? "" : mode, limit: limit)
    expect(
      stored.intervalMicros == authored.intervalMicros,
      "t_bw \(mode)\(limit ? " limited" : ""): stored Velocity \(velocity) plays a "
        + "\(stored.intervalMicros ?? 0) µs phase, the mode itself \(authored.intervalMicros ?? 0) µs")
    var plain = stored
    plain.smooth = false
    if limit {
      report("t_bw \(mode) (Velocity \(velocity)) 60 Hz, limited", measure(.transparentBlackWhite, plain))
    } else {
      reportOriginal("t_bw \(mode) (Velocity \(velocity)) 60 Hz", .transparentBlackWhite, plain,
        authoredMicros: tbwModePhaseMicros[mode]!)
    }
  }
}

/// Music flash events every 50 ms (20 per second), as the renderer plays them:
/// every accepted event is one visible change (a colour swap) and a Pro Strobe
/// flash also turns off `flashDurationSeconds` later. With the limit they all
/// share the six-changes-per-second window, like the Dart
/// VisualFlashChangeWindow; without it every event is played, as before.
func measureMusic(_ program: H.StrobeProgram, limit: Bool, everyMicros: Int64 = 50_000,
                  seconds: Int64 = 6) -> Measurement {
  let state = H.StrobeState(
    layer: H.StrobeLayer(id: "probe", program: program, opacity: 1,
      options: options(program, limit: limit)),
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
  let original = measureMusic(program, limit: false)
  print("\(program.rawValue) with music flash events every 50 ms without the limit: "
    + "\(String(format: "%.2f", original.changesPerSecond)) accepted events/s")
  expect(original.changesPerSecond == 20,
    "\(program.rawValue) without the limit played \(original.changesPerSecond) of 20 events/s")
  let m = measureMusic(program, limit: true)
  expect(m.changesPerSecond > 0, "\(program.rawValue) never reacted to music flash events")
  report("\(program.rawValue) with music flash events every 50 ms, limited", m)
}

/// Turning the limit on or off mid-strobe (a live change, or a new document
/// through rebind) keeps the light shown and restarts the periodic wait: the
/// next change comes one whole new phase later.
func expectToggleKeepsLight(_ name: String, viaRebind: Bool) {
  let layer = H.StrobeLayer(id: "probe", program: .backgroundColorLights, opacity: 1,
    options: options(.backgroundColorLights))
  let state = H.StrobeState(layer: layer, playing: true)
  for _ in 0..<4 { _ = state.advance(by: 16_667) }  // 67 ms: second phase (light on)
  for limit in [true, false] {
    let shown = state.frame
    if viaRebind {
      state.rebind(plan: Plan(playing: true), layer: layer.limitingFlashes(limit))
    } else {
      state.setLimitFlashes(limit)
    }
    expect(state.layer.options.limitFlashes == limit, "\(name): the limit did not switch to \(limit)")
    expect(state.frame == shown, "\(name): switching the limit to \(limit) changed the light")
    let phase = state.layer.options.intervalMicros!
    var elapsed: Int64 = 0
    while state.frame == shown && elapsed < 2_000_000 {
      _ = state.advance(by: 1_000)
      elapsed += 1_000
    }
    expect(abs(elapsed - phase) <= 1_000,
      "\(name): after switching the limit to \(limit) the next change came after \(elapsed) µs, "
        + "one new phase is \(phase) µs")
  }
}
expectToggleKeepsLight("live flash limit", viaRebind: false)
expectToggleKeepsLight("flash limit from a new document", viaRebind: true)

// A limit switched on mid-song admits music flashes from then on; switched
// off, every event plays again.
do {
  let state = H.StrobeState(layer: H.StrobeLayer(id: "probe", program: .backgroundSimpleDisco,
    opacity: 1, options: options(.backgroundSimpleDisco)), playing: true)
  let quiet = SceneRenderSignalEventV2(serial: 0, active: false, timestampMicros: 0, strength: 0, band: .low)
  func event(_ serial: Int64) -> Bool {
    let now = serial * 50_000
    let flash = SceneRenderSignalEventV2(serial: serial, active: true, timestampMicros: now, strength: 1, band: .broadband)
    return state.consume(SceneRenderSignalFrameV2(sessionId: 1, sequence: serial, audioTimestampMicros: now,
      available: true, fresh: true, musicActive: true, tonalAvailable: false,
      dynamics: [Float](repeating: 0.8, count: 6), channels: [Float](repeating: 0.8, count: 4),
      spectrumSummary: [Float](repeating: 0.6, count: 7), instantSpectrum: [Float](repeating: 0.6, count: 31),
      smoothedSpectrum: [Float](repeating: 0.6, count: 31), semantics: [Float](repeating: 0, count: 6),
      rhythm: [120, 0.5, 0, 0], onsets: [0, 0, 0, 0], tonal: [0, 0, 0],
      impact: quiet, accent: quiet, beat: quiet, flash: flash))
  }
  var serial: Int64 = 0
  var accepted = 0
  for _ in 0..<20 { serial += 1; if event(serial) { accepted += 1 } }
  expect(accepted == 20, "simple disco without the limit accepted \(accepted) of 20 events in 1 s")
  state.setLimitFlashes(true)
  accepted = 0
  for _ in 0..<20 { serial += 1; if event(serial) { accepted += 1 } }
  expect(accepted == 6, "simple disco with the limit switched on accepted \(accepted) events in 1 s, ceiling 6")
  state.setLimitFlashes(false)
  accepted = 0
  for _ in 0..<20 { serial += 1; if event(serial) { accepted += 1 } }
  expect(accepted == 20, "simple disco with the limit switched off accepted \(accepted) of 20 events in 1 s")
}

if failures > 0 {
  print("\(failures) strobe flash safety failure(s)")
  exit(1)
}
print("PASS strobe flash simulation")
