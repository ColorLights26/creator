import 'dart:convert';
import 'dart:typed_data';

import 'scene_render_signal_frame_v2.dart';

/// One captured publication, at its original host time and with original bytes.
final class SceneSignalSample {
  const SceneSignalSample({required this.hostTime, required this.frame});

  final Duration hostTime;
  final SceneRenderSignalFrameV2 frame;
}

/// Reads the existing `signals.bin` + `timeline.json` reference capture format.
///
/// No interpolation, normalization, event remapping, or musical interpretation
/// takes place here. A recording contains exactly one source session, as enforced
/// by the production recorder. Files alone do not certify real-device origin.
final class SceneSignalRecording {
  SceneSignalRecording._({
    required this.samples,
    required this.qaSessionSeed,
    required this.authoredFramesPerSecond,
    required this.observedFramesPerSecond,
    required this.synthetic,
  });

  factory SceneSignalRecording.fromBundle({
    required Uint8List signals,
    required String timelineJson,
    bool synthetic = false,
  }) {
    const maxFrames = 108000;
    if (signals.isEmpty ||
        signals.length % SceneRenderSignalFrameV2.byteLength != 0 ||
        signals.length ~/ SceneRenderSignalFrameV2.byteLength > maxFrames ||
        timelineJson.length > 32 * 1024 * 1024) {
      throw const FormatException('Invalid or oversized signal recording.');
    }
    final decoded = jsonDecode(timelineJson);
    if (decoded is! Map<String, dynamic> ||
        decoded['formatVersion'] != 1 ||
        decoded['kind'] != 'scene_timeline_reference_v1') {
      throw const FormatException('Unsupported scene timeline format.');
    }
    final seed = _nonNegativeInt(decoded['qaSessionSeed'], 'qaSessionSeed');
    final authored = _positiveNumber(
      decoded['authoredFramesPerSecond'],
      'authoredFramesPerSecond',
    );
    final observed = _positiveNumber(
      decoded['observedFramesPerSecond'],
      'observedFramesPerSecond',
    );
    if (authored < 1 ||
        authored > 240 ||
        authored != authored.roundToDouble()) {
      throw const FormatException(
        'Authored frame rate must be an integer from 1 to 240.',
      );
    }
    final rows = decoded['samples'];
    if (rows is! List ||
        rows.length < 3 ||
        rows.length != signals.length ~/ SceneRenderSignalFrameV2.byteLength) {
      throw const FormatException('Timeline and signal frame counts differ.');
    }
    final samples = <SceneSignalSample>[];
    var lastHost = -1;
    var lastMedia = -1;
    var lastSequence = -1;
    int? sessionId;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row is! Map<String, dynamic>) {
        throw FormatException('Invalid timeline sample $i.');
      }
      final host = _nonNegativeInt(row['hostTimeMicros'], 'hostTimeMicros');
      final media = _nonNegativeInt(row['mediaPtsMicros'], 'mediaPtsMicros');
      final SceneRenderSignalFrameV2 frame;
      try {
        frame = SceneRenderSignalFrameV2.fromBytes(
          Uint8List.sublistView(
            signals,
            i * SceneRenderSignalFrameV2.byteLength,
            (i + 1) * SceneRenderSignalFrameV2.byteLength,
          ),
        );
      } on ArgumentError catch (error) {
        throw FormatException('Invalid signal frame $i: $error');
      }
      sessionId ??= frame.sessionId;
      if (host <= lastHost ||
          media < lastMedia ||
          frame.audioTimestampMicros != media ||
          frame.sequence <= lastSequence ||
          frame.sessionId != sessionId) {
        throw FormatException('Discontinuous recording clocks at sample $i.');
      }
      final serials = row['eventSerials'];
      if (serials is! Map<String, dynamic> ||
          serials['impact'] != frame.impact.serial ||
          serials['accent'] != frame.accent.serial ||
          serials['beat'] != frame.beat.serial ||
          serials['flash'] != frame.flash.serial) {
        throw FormatException('Timeline event serial mismatch at sample $i.');
      }
      samples.add(
        SceneSignalSample(hostTime: Duration(microseconds: host), frame: frame),
      );
      lastHost = host;
      lastMedia = media;
      lastSequence = frame.sequence;
    }
    return SceneSignalRecording._(
      samples: List<SceneSignalSample>.unmodifiable(samples),
      qaSessionSeed: seed,
      authoredFramesPerSecond: authored,
      observedFramesPerSecond: observed,
      synthetic: synthetic,
    );
  }

  final List<SceneSignalSample> samples;
  final int qaSessionSeed;
  final double authoredFramesPerSecond;
  final double observedFramesPerSecond;

  /// Explicit test/demo provenance, never evidence of a recorded sensor session.
  final bool synthetic;

  Duration get capturedDuration => samples.last.hostTime;

  /// Holds the final publication for one authored frame so it is visible even
  /// when a display tick lands exactly on the final captured timestamp.
  Duration get duration =>
      capturedDuration +
      Duration(
        microseconds:
            (Duration.microsecondsPerSecond / authoredFramesPerSecond).round(),
      );

  Uint8List get signalBytes {
    final result = BytesBuilder(copy: false);
    for (final sample in samples) {
      result.add(sample.frame.toBytes());
    }
    return result.takeBytes();
  }

  String get timelineJson => const JsonEncoder.withIndent('  ').convert({
    'formatVersion': 1,
    'kind': 'scene_timeline_reference_v1',
    'qaSessionSeed': qaSessionSeed,
    'authoredFramesPerSecond': authoredFramesPerSecond,
    'observedFramesPerSecond': observedFramesPerSecond,
    'samples': [
      for (final sample in samples)
        {
          'hostTimeMicros': sample.hostTime.inMicroseconds,
          'mediaPtsMicros': sample.frame.audioTimestampMicros,
          'eventSerials': {
            'impact': sample.frame.impact.serial,
            'accent': sample.frame.accent.serial,
            'beat': sample.frame.beat.serial,
            'flash': sample.frame.flash.serial,
          },
        },
    ],
  });
}

int _nonNegativeInt(Object? value, String name) {
  if (value is! int || value < 0) {
    throw FormatException('$name must be a non-negative integer.');
  }
  return value;
}

double _positiveNumber(Object? value, String name) {
  if (value is! num || !value.isFinite || value <= 0) {
    throw FormatException('$name must be finite and positive.');
  }
  return value.toDouble();
}
