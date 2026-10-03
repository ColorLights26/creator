import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'scene_render_signal_frame_v2.dart';
import 'scene_signal_recording.dart';

class _EventTracker {
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

/// What the music is doing at one frame of a demo score.
///
/// The sustained layers ([pad], [sub], [air]) carry the loudness of a
/// section; the hits ([kick], [snare], [hat]) only fire on grid steps. A demo
/// is useful for judging a visual when it has contrast between sections: the
/// old demos were all hits with no sustained layer, so they read as flat.
class _Moment {
  const _Moment({
    this.music = true,
    this.bpm = 120,
    this.pad = 0,
    this.sub = 0,
    this.air = 0,
    this.kick = 0,
    this.snare = 0,
    this.hat = 0,
    this.flash = false,
    this.tag = 0,
  });

  static const silence = _Moment(music: false);

  final bool music;
  final double bpm;
  final double pad;
  final double sub;
  final double air;
  final double kick;
  final double snare;
  final double hat;
  final bool flash;

  /// Section badge read by the studio chart: 0 ambient, 1 build-up, 2 drop,
  /// 3 trap 808, 4 climax.
  final int tag;
}

/// Grid position handed to a score: [step] is the 1/16 note index, [onStep]
/// is true only on the frame where that step starts.
typedef _Score = _Moment Function(double t, int step, bool onStep);

double _ramp(double t, double from, double to) =>
    ((t - from) / (to - from)).clamp(0.0, 1.0);

double _lerp(double a, double b, double x) => a + (b - a) * x;

SceneSignalRecording _composeRecording({
  required double seconds,
  required _Score score,
  int qaSessionSeed = 26,
}) {
  const framesPerSecond = 30;
  final sampleCount = (seconds * framesPerSecond).round();
  final bytes = BytesBuilder(copy: false);
  final timeline = <Map<String, Object>>[];
  final impactTrack = _EventTracker();
  final accentTrack = _EventTracker();
  final beatTrack = _EventTracker();
  final flashTrack = _EventTracker();
  final smoothSpectrum = List<double>.filled(31, 0.0);

  var stepPhase = 0.0;
  var step = -1;
  var kickEnv = 0.0;
  var snareEnv = 0.0;
  var hatEnv = 0.0;
  var flow = 0.0;

  for (var i = 0; i < sampleCount; i++) {
    final host = (i * Duration.microsecondsPerSecond / framesPerSecond).round();
    final audioTime = 1000000 + host;
    final t = i / framesPerSecond;

    // Tempo can change between sections; the grid follows it smoothly.
    final tempo = score(t, math.max(step, 0), false).bpm;
    stepPhase += tempo / 60 * 4 / framesPerSecond;
    final onStep = stepPhase >= 1.0 || step < 0;
    if (onStep) {
      step++;
      stepPhase %= 1.0;
    }
    final m = score(t, step, onStep);
    final music = m.music;

    final kick = music && onStep ? m.kick : 0.0;
    final snare = music && onStep ? m.snare : 0.0;
    final hat = music && onStep ? m.hat : 0.0;
    kickEnv = music ? math.max(kick, kickEnv * 0.74) : 0.0;
    snareEnv = music ? math.max(snare, snareEnv * 0.78) : 0.0;
    hatEnv = music ? math.max(hat, hatEnv * 0.62) : 0.0;
    flow = music ? flow + (m.pad - flow) * 0.08 : 0.0;

    final bass = music ? math.max(m.sub, kickEnv).clamp(0.0, 1.0) : 0.0;
    final body = music ? math.max(m.pad, snareEnv).clamp(0.0, 1.0) : 0.0;
    final spark = music ? math.max(m.air, hatEnv).clamp(0.0, 1.0) : 0.0;
    final energy = music
        ? (0.38 * bass + 0.30 * body + 0.17 * spark + 0.15 * flow).clamp(
            0.0,
            1.0,
          )
        : 0.0;

    final isQuarter = onStep && step % 4 == 0;
    final beatStrength = music && isQuarter && (kick > 0 || m.sub > 0.3)
        ? math.max(kick, 0.6)
        : 0.0;
    final impact = impactTrack.sample(
      kick,
      audioTime,
      SceneRenderSignalEventBandV2.low,
    );
    final accent = accentTrack.sample(
      snare > 0 ? snare : hat,
      audioTime,
      snare > 0
          ? SceneRenderSignalEventBandV2.body
          : SceneRenderSignalEventBandV2.high,
    );
    final beatEvent = beatTrack.sample(
      beatStrength,
      audioTime,
      SceneRenderSignalEventBandV2.broadband,
    );
    final flash = flashTrack.sample(
      m.flash && kick > 0 ? 0.95 : 0.0,
      audioTime,
      SceneRenderSignalEventBandV2.broadband,
    );

    final spectrum = List<double>.generate(31, (band) {
      if (!music) return 0.0;
      final low = math.exp(-math.pow((band - 2.5) / 3.6, 2)) * bass;
      final mid = math.exp(-math.pow((band - 12.0) / 6.0, 2)) * body;
      final high = math.exp(-math.pow((band - 25.0) / 5.0, 2)) * spark;
      final shimmer = 0.88 + 0.12 * math.sin(band * 0.7 + t * 3.1);
      return ((low + mid + high) * shimmer).clamp(0.0, 1.0);
    }, growable: false);
    for (var b = 0; b < 31; b++) {
      final target = spectrum[b];
      smoothSpectrum[b] = !music
          ? 0.0
          : target > smoothSpectrum[b]
          ? smoothSpectrum[b] + (target - smoothSpectrum[b]) * 0.65
          : smoothSpectrum[b] * 0.85;
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
        math.max(kick, snare),
        flow,
        energy,
        music ? 18.0 : 0.0,
      ],
      channels: [bass, body, spark, flow],
      spectrumSummary: [
        energy,
        bass,
        body,
        flow,
        spark,
        math.max(snare, hat),
        energy * 0.3,
      ],
      instantSpectrum: spectrum,
      smoothedSpectrum: smoothSpectrum,
      semantics: [
        m.tag.toDouble(),
        0,
        music ? 0.85 : 0,
        music ? 0.9 : 0,
        energy,
        0,
      ],
      rhythm: [music ? m.bpm : 0, stepPhase, music ? 0.85 : 0, music ? 0.8 : 0],
      onsets: [kick, snare, hat, math.max(kick, snare)],
      tonalAvailable: music,
      tonal: [flow, music ? 0.5 : 0, 0],
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
  }

  return SceneSignalRecording.fromBundle(
    signals: bytes.takeBytes(),
    timelineJson: jsonEncode({
      'formatVersion': 1,
      'kind': 'scene_timeline_reference_v1',
      'qaSessionSeed': qaSessionSeed,
      'authoredFramesPerSecond': framesPerSecond,
      'observedFramesPerSecond': framesPerSecond,
      'samples': timeline,
    }),
    synthetic: true,
  );
}

/// Four-on-the-floor drop at [bpm]: kick every beat, snare on 2 and 4,
/// off-beat hats, sustained bass and pad. [level] scales the whole section.
_Moment _dropAt(int step, {double bpm = 128, double level = 1, int tag = 2}) {
  final s = step % 16;
  return _Moment(
    bpm: bpm,
    pad: 0.72 * level,
    sub: 0.85 * level,
    air: 0.55 * level,
    kick: s % 4 == 0 ? level : 0,
    snare: s == 4 || s == 12 ? 0.9 * level : 0,
    hat: s % 4 == 2 ? 0.8 * level : 0.35 * level,
    flash: true,
    tag: tag,
  );
}

/// Riser: snare hits get denser (every 4 → 2 → 1 steps) and everything
/// climbs from [from] to [to] across the section progress [x] (0..1).
_Moment _buildUp(
  int step,
  double x, {
  double bpm = 128,
  double from = 0.3,
  double to = 0.85,
}) {
  final every = x < 0.5 ? 4 : (x < 0.8 ? 2 : 1);
  final level = _lerp(from, to, x);
  return _Moment(
    bpm: bpm,
    pad: level * 0.8,
    sub: 0.1 + 0.2 * x,
    air: _lerp(0.15, 0.85, x),
    snare: step % every == 0 ? _lerp(0.4, 0.95, x) : 0,
    hat: step.isOdd ? 0.3 + 0.4 * x : 0,
    tag: 1,
  );
}

/// 1. Demo: a tour of every situation in 32 s — calm, build-up, the drop (the
/// loudest part), trap, climax and a fade to silence.
SceneSignalRecording createDynamicShowcaseSignalRecording() {
  return _composeRecording(
    seconds: 32,
    score: (t, step, onStep) {
      if (t < 6) {
        final breath = 0.5 + 0.5 * math.sin(t * 1.1);
        return _Moment(bpm: 75, pad: 0.18 + 0.14 * breath, air: 0.1, tag: 0);
      }
      if (t < 12) return _buildUp(step, _ramp(t, 6, 12));
      if (t < 12.6) return _Moment.silence;
      if (t < 19) return _dropAt(step);
      if (t < 25) {
        final s = step % 16;
        return _Moment(
          bpm: 140,
          pad: 0.35,
          sub: s == 0 || s == 10 ? 0.9 : 0.55,
          air: 0.4,
          kick: s == 0 || s == 10 ? 0.85 : 0,
          snare: s == 8 ? 0.85 : 0,
          hat: 0.55,
          tag: 3,
        );
      }
      final fade = 1 - _ramp(t, 30, 32);
      if (fade <= 0.02) return _Moment.silence;
      return _dropAt(step, bpm: 132, level: 0.95 * fade, tag: 4);
    },
  );
}

/// 2. EDM: intro, build-up, a second of silence, the drop, a breakdown and
/// a second drop. 32 s at 128 BPM.
SceneSignalRecording createEdmClubDropSignalRecording() {
  return _composeRecording(
    seconds: 32,
    score: (t, step, onStep) {
      if (t < 4) {
        return _Moment(
          pad: 0.22,
          air: 0.12,
          hat: step % 4 == 2 ? 0.35 : 0,
          tag: 0,
        );
      }
      if (t < 12) return _buildUp(step, _ramp(t, 4, 12), from: 0.25, to: 0.9);
      if (t < 13) return _Moment.silence;
      if (t < 21) return _dropAt(step);
      if (t < 25) {
        return _Moment(
          pad: 0.38,
          sub: 0.15,
          air: 0.2,
          hat: step % 4 == 2 ? 0.4 : 0,
          tag: 0,
        );
      }
      if (t < 27) return _buildUp(step, _ramp(t, 25, 27), from: 0.4, to: 0.9);
      final fade = 1 - _ramp(t, 31, 32);
      return _dropAt(step, level: math.max(0.05, fade), tag: 4);
    },
  );
}

/// 3. Trap: half-time verses with steady hats, then heavy 808 drops with
/// hat rolls, a silence gap and a second drop. 32 s at 140 BPM.
SceneSignalRecording createTrap808SignalRecording() {
  _Moment verse(int step) {
    final s = step % 16;
    return _Moment(
      bpm: 140,
      pad: 0.32,
      sub: 0.22,
      air: 0.2,
      kick: s == 0 || s == 10 ? 0.6 : 0,
      snare: s == 8 ? 0.7 : 0,
      hat: step.isEven ? 0.45 : 0,
      tag: 3,
    );
  }

  _Moment drop(int step, double level) {
    final s = step % 16;
    final roll = s >= 12; // 1/16 hat rolls at the end of each bar
    return _Moment(
      bpm: 140,
      pad: 0.5 * level,
      sub: (s == 0 || s == 6 || s == 10 ? 1.0 : 0.7) * level,
      air: 0.5 * level,
      kick: s == 0 || s == 6 || s == 10 ? level : 0,
      snare: s == 8 ? 0.95 * level : 0,
      hat: roll || step.isEven ? 0.7 * level : 0,
      flash: true,
      tag: 3,
    );
  }

  return _composeRecording(
    seconds: 32,
    score: (t, step, onStep) {
      if (t < 6) return verse(step);
      if (t < 8) {
        final x = _ramp(t, 6, 8);
        return _Moment(
          bpm: 140,
          pad: 0.35 + 0.25 * x,
          sub: 0.2,
          air: 0.3 + 0.5 * x,
          hat: 0.4 + 0.5 * x,
          tag: 1,
        );
      }
      if (t < 16) return drop(step, 1);
      if (t < 16.8) return _Moment.silence;
      if (t < 22) return verse(step);
      if (t < 30) return drop(step, 1);
      final fade = 1 - _ramp(t, 30, 32);
      return fade <= 0.02 ? _Moment.silence : drop(step, fade);
    },
  );
}

/// 4. Ambient: irregular breathing pads (never the same twice), a soft pulse
/// in the middle, a near-silent dip and a final swell. 32 s.
SceneSignalRecording createAmbientChilloutSignalRecording() {
  final random = math.Random(75);
  final twinkles = List<bool>.generate(2048, (_) => random.nextDouble() < 0.18);
  return _composeRecording(
    seconds: 32,
    score: (t, step, onStep) {
      final breath =
          0.5 +
          0.30 * math.sin(t * 0.55) +
          0.15 * math.sin(t * 1.37 + 1.2) +
          0.05 * math.sin(t * 3.1);
      final twinkle = twinkles[step % twinkles.length] ? 0.35 : 0.0;
      if (t < 12) {
        return _Moment(
          bpm: 72,
          pad: 0.15 + 0.75 * breath,
          air: 0.15 + 0.3 * breath,
          hat: twinkle,
          tag: 0,
        );
      }
      if (t < 20) {
        return _Moment(
          bpm: 72,
          pad: 0.3 + 0.25 * breath,
          sub: 0.3,
          air: 0.2,
          kick: step % 4 == 0 ? 0.45 : 0,
          hat: twinkle,
          tag: 0,
        );
      }
      if (t < 22.5) return const _Moment(bpm: 72, pad: 0.05, tag: 0);
      final swell = _ramp(t, 22.5, 29) * (1 - _ramp(t, 30, 32));
      return _Moment(
        bpm: 72,
        pad: 0.1 + 0.7 * swell,
        air: 0.3 * swell,
        hat: twinkle * swell,
        tag: 0,
      );
    },
  );
}

/// 5. Cortes: full-power music that stops and restarts abruptly — short
/// gaps, a long silence and stutters — to see how a visual handles silence
/// and sudden starts. 24 s at 124 BPM.
SceneSignalRecording createCutsSignalRecording() {
  const cuts = [
    (3.0, 4.0),
    (5.5, 6.0),
    (9.0, 11.0),
    (11.5, 12.0),
    (12.5, 13.0),
    (13.5, 14.0),
    (20.0, 22.0),
  ];
  return _composeRecording(
    seconds: 24,
    score: (t, step, onStep) {
      for (final (from, to) in cuts) {
        if (t >= from && t < to) return _Moment.silence;
      }
      if (t >= 23) return _Moment.silence;
      return _dropAt(step, bpm: 124);
    },
  );
}

/// 5. Spectral Sweep & Stress Test (20 seconds).
/// Frequency sweep 20 Hz to 20 kHz (0-15s), silence freeze (15-17s), noise bursts (17-20s).
SceneSignalRecording createSpectralSweepSignalRecording() {
  const framesPerSecond = 30;
  const sampleCount = 20 * framesPerSecond;
  final bytes = BytesBuilder(copy: false);
  final timeline = <Map<String, Object>>[];
  final impactTrack = _EventTracker();
  final accentTrack = _EventTracker();
  final beatTrack = _EventTracker();
  final flashTrack = _EventTracker();

  final smoothSpectrum = List<double>.filled(31, 0.0);

  for (var i = 0; i < sampleCount; i++) {
    final host = (i * Duration.microsecondsPerSecond / framesPerSecond).round();
    final audioTime = 1000000 + host;
    final t = i / framesPerSecond;

    final isSweep = t < 15.0;
    final isSilence = t >= 15.0 && t < 17.0;
    final isBurst = t >= 17.0;

    final centerBand = isSweep ? (t / 15.0) * 30.0 : 0.0;
    final burstPulse = isBurst && ((t * 4.0).floor() % 2 == 0);

    final bass = isSweep && centerBand < 8.0 ? 0.95 : (burstPulse ? 0.95 : 0.0);
    final body = isSweep && centerBand >= 8.0 && centerBand < 20.0 ? 0.95 : (burstPulse ? 0.90 : 0.0);
    final spark = isSweep && centerBand >= 20.0 ? 0.95 : (burstPulse ? 0.95 : 0.0);
    final energy = isSilence ? 0.0 : (isBurst ? (burstPulse ? 1.0 : 0.0) : 0.85);

    final impact = impactTrack.sample(burstPulse ? 0.95 : 0.0, audioTime, SceneRenderSignalEventBandV2.broadband);
    final accent = accentTrack.sample(0.0, audioTime, SceneRenderSignalEventBandV2.none);
    final beatEvent = beatTrack.sample(burstPulse ? 0.95 : 0.0, audioTime, SceneRenderSignalEventBandV2.broadband);
    final flash = flashTrack.sample(burstPulse ? 0.90 : 0.0, audioTime, SceneRenderSignalEventBandV2.broadband);

    final spectrum = List<double>.generate(31, (band) {
      if (isSilence) return 0.0;
      if (isBurst) return burstPulse ? 1.0 : 0.0;
      // Gaussian peak centered at centerBand
      return math.exp(-math.pow((band - centerBand) / 1.8, 2)).clamp(0.0, 1.0);
    }, growable: false);

    for (var b = 0; b < 31; b++) {
      smoothSpectrum[b] = spectrum[b];
    }

    final frame = SceneRenderSignalFrameV2(
      sessionId: 1,
      sequence: i + 1,
      audioTimestampMicros: audioTime,
      available: true,
      fresh: true,
      musicActive: !isSilence,
      dynamics: [energy, energy, burstPulse ? 1.0 : 0.0, 0.7, energy, 18.0],
      channels: [bass, body, spark, 0.7],
      spectrumSummary: [energy, bass, body, 0.7, spark, 0.0, energy * 0.3],
      instantSpectrum: spectrum,
      smoothedSpectrum: smoothSpectrum,
      semantics: [0, 0, 0.8, 0.8, energy, 0],
      rhythm: [120.0, (t * 2.0) % 1.0, 0.8, 0.8],
      onsets: [burstPulse ? 1.0 : 0.0, 0.0, 0.0, burstPulse ? 1.0 : 0.0],
      tonalAvailable: !isSilence,
      tonal: [0.7, 0.5, 0],
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
