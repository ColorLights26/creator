import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'scene_render_signal_frame_v2.dart';
import 'scene_signal_recording.dart';

/// Deterministic demonstration only. These are NOT measured microphone values.
/// Includes silence, sustained music, and distinct events to exercise wiring.
SceneSignalRecording createSyntheticSceneSignalRecording() {
  const framesPerSecond = 30;
  const sampleCount = 240;
  final bytes = BytesBuilder(copy: false);
  final timeline = <Map<String, Object>>[];
  var serial = 0;
  var lastEventTime = 0;
  for (var i = 0; i < sampleCount; i++) {
    final host = (i * Duration.microsecondsPerSecond / framesPerSecond).round();
    final audioTime = 1000000 + host;
    final music = i >= 30 && i < 210;
    final pulse = music && i % 15 == 0;
    if (pulse) {
      serial++;
      lastEventTime = audioTime;
    }
    final phase = (i % 15) / 15;
    final energy = music ? 0.35 + 0.3 * (1 + math.sin(i / 20)) / 2 : 0.0;
    final accent = music ? math.pow(1 - phase, 4).toDouble() : 0.0;
    final event = SceneRenderSignalEventV2(
      serial: serial,
      active: pulse,
      timestampMicros: lastEventTime,
      strength: pulse ? 0.8 : 0,
      band:
          pulse
              ? SceneRenderSignalEventBandV2.low
              : SceneRenderSignalEventBandV2.none,
    );
    const inactive = SceneRenderSignalEventV2(
      serial: 0,
      active: false,
      timestampMicros: 0,
      strength: 0,
      band: SceneRenderSignalEventBandV2.none,
    );
    final spectrum = List<double>.generate(
      SceneRenderSignalFrameV2.spectrumBandCount,
      (band) =>
          music
              ? energy *
                  (0.25 + 0.75 * math.pow(math.sin(band * 0.21 + i * 0.03), 2))
              : 0,
      growable: false,
    );
    final frame = SceneRenderSignalFrameV2(
      sessionId: 1,
      sequence: i + 1,
      audioTimestampMicros: audioTime,
      available: true,
      fresh: true,
      musicActive: music,
      dynamics: [energy, energy, accent, energy, energy, music ? 18 : 0],
      channels: [accent, energy, accent * 0.7, energy],
      spectrumSummary: [
        energy,
        accent,
        energy,
        energy * 0.8,
        energy * 0.6,
        accent,
        energy * 0.3,
      ],
      instantSpectrum: spectrum,
      smoothedSpectrum: spectrum,
      semantics: [0, 0, music ? 0.8 : 0, music ? 0.9 : 0, energy, 0],
      rhythm: [
        music ? 120 : 0,
        music ? phase : 0,
        music ? 0.95 : 0,
        music ? 0.9 : 0,
      ],
      onsets: [accent, accent * 0.5, accent * 0.2, accent],
      tonalAvailable: music,
      tonal: [energy, music ? 0.5 : 0, 0],
      impact: event,
      accent: inactive,
      beat: event,
      flash: inactive,
    );
    bytes.add(frame.toBytes());
    timeline.add({
      'hostTimeMicros': host,
      'mediaPtsMicros': audioTime,
      'eventSerials': {
        'impact': serial,
        'accent': 0,
        'beat': serial,
        'flash': 0,
      },
    });
  }
  return SceneSignalRecording.fromBundle(
    signals: bytes.takeBytes(),
    timelineJson: jsonEncode({
      'formatVersion': 1,
      'kind': 'scene_timeline_reference_v1',
      'qaSessionSeed': 26,
      'authoredFramesPerSecond': framesPerSecond,
      'observedFramesPerSecond': framesPerSecond,
      'samples': timeline,
    }),
    synthetic: true,
  );
}
