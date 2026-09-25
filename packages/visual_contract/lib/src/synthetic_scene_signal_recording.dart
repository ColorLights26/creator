import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'scene_render_signal_frame_v2.dart';
import 'scene_signal_recording.dart';

/// Deterministic musical sketch, NOT a recording or a sensor model.
/// Quiet opening, build, break, stronger return and release over 32 seconds.
SceneSignalRecording createSyntheticSceneSignalRecording() {
  const framesPerSecond = 30;
  const sampleCount = 32 * framesPerSecond;
  final random = math.Random(26);
  final bytes = BytesBuilder(copy: false);
  final timeline = <Map<String, Object>>[];
  final impactTrack = _DemoEvent();
  final accentTrack = _DemoEvent();
  final beatTrack = _DemoEvent();
  final flashTrack = _DemoEvent();
  var phase = 0.0;
  var beatIndex = -1;
  var wasMusic = false;
  var bass = 0.0;
  var body = 0.0;
  var spark = 0.0;
  var flow = 0.0;
  final smoothSpectrum = List<double>.filled(31, 0);
  for (var i = 0; i < sampleCount; i++) {
    final host = (i * Duration.microsecondsPerSecond / framesPerSecond).round();
    final audioTime = 1000000 + host;
    final t = i / framesPerSecond;
    final music = t >= 1 && t < 31 && !(t >= 14 && t < 16);
    final level = t < 7
        ? .3
        : t < 14
        ? .3 + .5 * (t - 7) / 7
        : t < 24
        ? .85
        : .85 - .65 * (t - 24) / 7;
    final bpm = 110 + 5 * math.sin(t * .24) + (t >= 16 ? 8 : 0);
    final previousPhase = phase;
    phase = music ? (wasMusic ? phase + bpm / (60 * framesPerSecond) : 0) : 0;
    final beat = music && (!wasMusic || phase >= 1);
    if (beat) {
      phase %= 1;
      beatIndex++;
    }
    final offbeat = music && !beat && previousPhase < .56 && phase >= .56;
    final position = beatIndex % 4;
    final kick =
        music &&
        ((beat && (position == 0 || position == 2)) ||
            (offbeat && level > .6 && random.nextDouble() < .35));
    final snare = beat && (position == 1 || position == 3);
    final hat = offbeat && random.nextDouble() < .85;
    final beatStrength = beat
        ? (.4 + .5 * level) * (.85 + .15 * random.nextDouble())
        : 0.0;
    final kickStrength = kick
        ? (.35 + .6 * level) * (.75 + .25 * random.nextDouble())
        : 0.0;
    final accentStrength = snare
        ? (.25 + .5 * level) * (.8 + .2 * random.nextDouble())
        : hat
        ? (.15 + .3 * level) * (.7 + .3 * random.nextDouble())
        : 0.0;
    // Distinct attack/release envelopes keep channels from moving in lockstep.
    bass = music ? math.max(kickStrength, bass * .79) : 0;
    body = music
        ? body + ((.12 + .45 * level + (snare ? .25 : 0)) - body) * .16
        : 0;
    spark = music ? math.max(accentStrength, spark * .62) : 0;
    flow = music
        ? flow + ((.18 + .55 * level + .08 * math.sin(t * .7)) - flow) * .06
        : 0;
    final energy = music
        ? (.15 * level + .4 * bass + .25 * body + .2 * flow).clamp(0.0, 1.0)
        : 0.0;
    final impact = impactTrack.sample(
      kickStrength,
      audioTime,
      SceneRenderSignalEventBandV2.low,
    );
    final accent = accentTrack.sample(
      accentStrength,
      audioTime,
      snare
          ? SceneRenderSignalEventBandV2.body
          : SceneRenderSignalEventBandV2.high,
    );
    final beatEvent = beatTrack.sample(
      beatStrength,
      audioTime,
      SceneRenderSignalEventBandV2.broadband,
    );
    final flash = flashTrack.sample(
      0,
      audioTime,
      SceneRenderSignalEventBandV2.none,
    );
    final spectrum = List<double>.generate(31, (band) {
      if (!music) return 0;
      final low = math.exp(-math.pow((band - 3) / 5, 2)) * bass;
      final mid = math.exp(-math.pow((band - 13) / 8, 2)) * body;
      final high = math.exp(-math.pow((band - 25) / 6, 2)) * spark;
      return ((low + mid + high) * (.8 + .2 * math.sin(band * .7 + t))).clamp(
        0.0,
        1.0,
      );
    }, growable: false);
    for (var band = 0; band < spectrum.length; band++) {
      smoothSpectrum[band] = music
          ? smoothSpectrum[band] + (spectrum[band] - smoothSpectrum[band]) * .18
          : 0;
    }
    final frame = SceneRenderSignalFrameV2(
      sessionId: 1,
      sequence: i + 1,
      audioTimestampMicros: audioTime,
      available: true,
      fresh: true,
      musicActive: music,
      dynamics: [
        energy,
        energy,
        math.max(kickStrength, accentStrength),
        flow,
        energy,
        music ? 18 : 0,
      ],
      channels: [bass, body, spark, flow],
      spectrumSummary: [
        energy,
        bass,
        body,
        flow,
        spark,
        accentStrength,
        energy * .3,
      ],
      instantSpectrum: spectrum,
      smoothedSpectrum: smoothSpectrum,
      semantics: [0, 0, music ? .8 : 0, music ? .9 : 0, energy, 0],
      rhythm: [
        music ? bpm : 0,
        phase,
        music ? .65 + .25 * level : 0,
        music ? .7 : 0,
      ],
      onsets: [
        kickStrength,
        snare ? accentStrength : 0,
        hat ? accentStrength : 0,
        math.max(kickStrength, accentStrength),
      ],
      tonalAvailable: music,
      tonal: [flow, music ? .5 : 0, 0],
      impact: impact,
      accent: accent,
      beat: beatEvent,
      flash: flash,
    );
    bytes.add(frame.toBytes());
    timeline.add({
      'hostTimeMicros': host,
      'mediaPtsMicros': audioTime,
      'eventSerials': {
        'impact': impact.serial,
        'accent': accent.serial,
        'beat': beatEvent.serial,
        'flash': flash.serial,
      },
    });
    wasMusic = music;
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

class _DemoEvent {
  int _serial = 0;
  int _timestamp = 0;

  SceneRenderSignalEventV2 sample(
    double strength,
    int time,
    SceneRenderSignalEventBandV2 band,
  ) {
    if (strength > 0) {
      _serial++;
      _timestamp = time;
    }
    return SceneRenderSignalEventV2(
      serial: _serial,
      active: strength > 0,
      timestampMicros: _timestamp,
      strength: strength,
      band: strength > 0 ? band : SceneRenderSignalEventBandV2.none,
    );
  }
}
