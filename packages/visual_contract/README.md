# Visual contract

The exact production `SceneRenderSignalFrameV2` codec, extracted without changing
its 520-byte v2 layout. Pure Dart; no Flutter, sensors, Firebase, or third-party
runtime dependencies. Production's `VisualRenderFrame` adapter remains in
`globalkernel`, outside this package.

`SceneSignalRecording.fromBundle(signals: ..., timelineJson: ...)` reads the
existing capture format. It verifies header versions, frame counts, monotonic
clocks, single-session continuity, and timeline/event agreement. It preserves
the captured timestamps, seed, serials, flags, and float32 values. The final
sample holds for one authored frame before a loop restarts.

Drive `SceneSignalReplay.advance(elapsed)` from the compositor's scene clock.
Before submitting a batch with `resetRequired`, reset compositor state using
`recording.qaSessionSeed`. Deliver **every sample** in order, not only the last,
so transient events are not discarded. Backward seeks and loop boundaries reset
the replay cursor; no source timestamp, event serial, or session ID is invented.
After a jump across entire loops, replay starts at the current loop; missed loops
are not burst-replayed. No second timer runs in this package.

Seed storage is lossless and never converts the seed to a floating-point value.
The creator's native shader ABI supports an exact uint32 seed from `0` through
`4294967295`; that consumer rejects recordings outside its supported range before
playback. Modulo, clamping, or float32 rounding cannot be called exact replay.
Reset the compositor with the same supported seed before the first publication,
each loop, and any backward seek; never substitute a fresh random seed.

The bundled fixture is explicitly **synthetic**, useful for wiring only. A file
using the capture schema does not establish device provenance. Import actual
`signals.bin` and `timeline.json` artifacts to evaluate recorded musical input.
No real recordings were bundled with this kit.

Verify with `dart run test/contract_test.dart`. These SDK-only checks intentionally
need no testing dependency. Regenerate the synthetic fixture with
`dart run tool/write_synthetic_fixture.dart`.
