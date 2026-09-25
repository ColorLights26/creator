import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:visual_contract/visual_contract.dart';

// SDK-only executable checks; run `dart run test/contract_test.dart`.
void main() {
  _codecCompatibility();
  _recordingValidation();
  _replay();
  stdout.writeln(
    'visual_contract: codec, recording, and replay checks passed.',
  );
}

void _codecCompatibility() {
  final fixture =
      File.fromUri(
        Platform.script.resolve('fixtures/production_v2.golden.bin'),
      ).readAsBytesSync();
  final frame = SceneRenderSignalFrameV2.fromBytes(fixture);
  _expect(SceneRenderSignalFrameV2.byteLength == 520, 'unchanged wire length');
  _expect(frame.sessionId == 17 && frame.sequence == 91, '64-bit clocks');
  _expect(
    frame.available && frame.fresh && frame.musicActive && frame.tonalAvailable,
    'wire flags',
  );
  _expect(frame.dynamics[5] == 18 && frame.rhythm[0] == 128, 'vector offsets');
  _expect((frame.instantSpectrum[30] - .3).abs() < 1e-6, 'spectrum offset');
  _expect(frame.impact.serial == 41 && frame.impact.active, 'impact payload');
  _expect(
    frame.accent.band == SceneRenderSignalEventBandV2.high,
    'event bands',
  );
  _expect(
    frame.beat.timestampMicros == 88000 && frame.flash.timestampMicros == 89000,
    'event times are not remapped',
  );
  _expect(
    _sameBytes(frame.toBytes(), fixture),
    'byte parity with pre-extraction layout',
  );
  final synthetic = createSyntheticSceneSignalRecording();
  final distinct = SceneRenderSignalFrameV2.fromBytes(
    synthetic.samples[31].frame.toBytes(),
  );
  _expect(
    _sameBytes(distinct.toBytes(), synthetic.samples[31].frame.toBytes()),
    'float32 identity',
  );

  for (final offset in [0, 4, 6, 8, 12, 444, 445, 446]) {
    final corrupted = Uint8List.fromList(fixture);
    corrupted[offset] = 255;
    _throwsFormat(
      () => SceneRenderSignalFrameV2.fromBytes(corrupted),
      'invalid header or event byte $offset',
    );
  }
  final nan = Uint8List.fromList(fixture);
  ByteData.sublistView(nan).setFloat32(40, double.nan, Endian.little);
  _throwsFormat(
    () => SceneRenderSignalFrameV2.fromBytes(nan),
    'nonfinite float',
  );
  _throwsFormat(
    () => SceneRenderSignalFrameV2.fromBytes(Uint8List(519)),
    'truncated frame',
  );
}

void _recordingValidation() {
  final recording = createSyntheticSceneSignalRecording();
  _expect(recording.synthetic, 'honest synthetic provenance');
  _expect(
    recording.qaSessionSeed == 26 && recording.samples.length == 240,
    'seed and count',
  );
  final bytes = recording.signalBytes;
  final loaded = SceneSignalRecording.fromBundle(
    signals: bytes,
    timelineJson: recording.timelineJson,
  );
  _expect(_sameBytes(loaded.signalBytes, bytes), 'recording byte parity');
  final highSeedTimeline =
      jsonDecode(recording.timelineJson) as Map<String, dynamic>;
  highSeedTimeline['qaSessionSeed'] = 0xffffffff;
  final highSeedRecording = SceneSignalRecording.fromBundle(
    signals: bytes,
    timelineJson: jsonEncode(highSeedTimeline),
  );
  _expect(
    highSeedRecording.qaSessionSeed == 0xffffffff,
    'large seed preserved without float32 rounding',
  );

  void corrupt(void Function(Map<String, dynamic>) edit, String label) {
    final timeline = jsonDecode(recording.timelineJson) as Map<String, dynamic>;
    edit(timeline);
    _throwsFormat(
      () => SceneSignalRecording.fromBundle(
        signals: bytes,
        timelineJson: jsonEncode(timeline),
      ),
      label,
    );
  }

  corrupt((json) => json['formatVersion'] = 2, 'timeline version');
  corrupt((json) => json['kind'] = 'other', 'timeline kind');
  corrupt((json) => json['samples'].removeLast(), 'count mismatch');
  corrupt(
    (json) => json['samples'][1]['hostTimeMicros'] = 0,
    'host time regression',
  );
  corrupt((json) => json['samples'][1]['mediaPtsMicros'] = 1, 'media mismatch');
  corrupt(
    (json) => json['samples'][31]['eventSerials']['beat'] = 999,
    'event mismatch',
  );
  corrupt((json) => json['qaSessionSeed'] = -1, 'invalid seed');
  corrupt((json) => json['authoredFramesPerSecond'] = 0, 'invalid cadence');
  corrupt((json) => json['authoredFramesPerSecond'] = 1e-300, 'unsafe cadence');
  final sessionMismatch = Uint8List.fromList(bytes);
  ByteData.sublistView(sessionMismatch).setInt64(520 + 16, 999, Endian.little);
  _throwsFormat(
    () => SceneSignalRecording.fromBundle(
      signals: sessionMismatch,
      timelineJson: recording.timelineJson,
    ),
    'session change',
  );
  final sequenceMismatch = Uint8List.fromList(bytes);
  ByteData.sublistView(sequenceMismatch).setInt64(520 + 24, 1, Endian.little);
  _throwsFormat(
    () => SceneSignalRecording.fromBundle(
      signals: sequenceMismatch,
      timelineJson: recording.timelineJson,
    ),
    'sequence regression',
  );
  _throwsFormat(
    () => SceneSignalRecording.fromBundle(
      signals: Uint8List.sublistView(bytes, 1),
      timelineJson: recording.timelineJson,
    ),
    'partial final frame',
  );
}

void _replay() {
  final recording = createSyntheticSceneSignalRecording();
  final replay = SceneSignalReplay(recording);
  var batch = replay.advance(Duration.zero);
  _expect(
    batch.resetRequired && batch.samples.length == 1 && batch.cycle == 0,
    'initial reset',
  );
  batch = replay.advance(Duration.zero);
  _expect(
    !batch.resetRequired && batch.samples.isEmpty,
    'paused clock publishes nothing',
  );
  batch = replay.advance(const Duration(milliseconds: 1200));
  _expect(batch.samples.length == 36, 'no samples lost on slow display tick');
  _expect(
    batch.samples.any((s) => s.frame.beat.active),
    'intermediate beat survives',
  );
  _expect(
    batch.samples.where((s) => s.frame.beat.active).first.frame.beat.serial ==
        1,
    'original serial retained',
  );
  batch = replay.advance(const Duration(milliseconds: 100));
  _expect(
    batch.resetRequired && batch.samples.length == 4,
    'backward seek reconstructs from start',
  );
  batch = replay.advance(recording.capturedDuration);
  _expect(
    batch.samples.last.frame.sequence == 240 && batch.cycle == 0,
    'final captured frame retained',
  );
  batch = replay.advance(recording.duration);
  _expect(
    batch.resetRequired &&
        batch.cycle == 1 &&
        batch.samples.single.frame.sequence == 1,
    'loop boundary resets original session',
  );
  batch = replay.advance(recording.duration * 5 + const Duration(seconds: 1));
  _expect(
    batch.resetRequired && batch.cycle == 5 && batch.samples.length == 31,
    'large skip resets only current loop',
  );
  replay.reset();
  batch = replay.advance(recording.duration * 2, loop: false);
  _expect(
    batch.resetRequired && batch.completed && batch.samples.length == 240,
    'nonloop completion delivers all frames',
  );
  batch = replay.advance(recording.duration * 3, loop: false);
  _expect(
    batch.samples.isEmpty && batch.completed,
    'completed recording does not repeat events',
  );
  batch = replay.advance(Duration.zero, loop: false);
  _expect(batch.resetRequired && !batch.completed, 'restart after completion');
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void _expect(bool condition, String label) {
  if (!condition) throw StateError('Failed: $label');
}

void _throwsFormat(void Function() action, String label) {
  try {
    action();
  } on FormatException {
    return;
  }
  throw StateError('Expected FormatException: $label');
}
