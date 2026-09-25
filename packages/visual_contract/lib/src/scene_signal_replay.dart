import 'scene_signal_recording.dart';

/// All publications due since the preceding call, including transient events.
/// Deliver these in order; selecting only the last frame can lose a beat.
final class SceneSignalReplayBatch {
  const SceneSignalReplayBatch({
    required this.samples,
    required this.position,
    required this.cycle,
    required this.resetRequired,
    required this.completed,
  });

  final List<SceneSignalSample> samples;
  final Duration position;
  final int cycle;

  /// Reset compositor state and seed BEFORE delivering [samples]. Source session
  /// IDs, serials, timestamps, and payloads deliberately remain byte-for-byte
  /// original; the same serial becomes eligible again only after this reset.
  final bool resetRequired;
  final bool completed;
}

/// Driven only by the host's paused/resumed scene clock, never a second timer.
final class SceneSignalReplay {
  SceneSignalReplay(this.recording);

  final SceneSignalRecording recording;
  int _lastElapsed = -1;
  int _lastCycle = -1;
  int _nextSample = 0;
  bool? _lastLoop;

  void reset() {
    _lastElapsed = -1;
    _lastCycle = -1;
    _nextSample = 0;
    _lastLoop = null;
  }

  SceneSignalReplayBatch advance(Duration elapsed, {bool loop = true}) {
    final micros = elapsed.inMicroseconds;
    if (micros < 0) {
      throw ArgumentError.value(elapsed, 'elapsed', 'Must be non-negative.');
    }
    final length = recording.duration.inMicroseconds;
    final cycle = loop ? micros ~/ length : 0;
    final position = loop ? micros % length : micros.clamp(0, length);
    final resetRequired =
        _lastElapsed < 0 ||
        micros < _lastElapsed ||
        cycle != _lastCycle ||
        _lastLoop != loop;
    if (resetRequired) _nextSample = 0;
    final due = <SceneSignalSample>[];
    while (_nextSample < recording.samples.length &&
        recording.samples[_nextSample].hostTime.inMicroseconds <= position) {
      due.add(recording.samples[_nextSample++]);
    }
    _lastElapsed = micros;
    _lastCycle = cycle;
    _lastLoop = loop;
    return SceneSignalReplayBatch(
      samples: List<SceneSignalSample>.unmodifiable(due),
      position: Duration(microseconds: position),
      cycle: cycle,
      resetRequired: resetRequired,
      completed: !loop && micros >= length,
    );
  }
}
