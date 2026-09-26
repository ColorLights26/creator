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

/// 1. Dynamic Multicase Showcase (32 seconds, 960 frames @ 30 FPS).
/// Automatically cycles through 5 distinct musical scenarios every 6.4 seconds:
/// - Phase 0 (0-6.4s): Ambient Pad & Harmonic Breaths (Soft & Flowing)
/// - Phase 1 (6.4-12.8s): Build-up & Riser with Accelerating Snare & Filter Sweep
/// - Phase 2 (12.8-19.2s): THE DROP (EDM 128 BPM, Heavy Bass & Punchy 4-on-the-floor Kick)
/// - Phase 3 (19.2-25.6s): Trap 808 & Fast Hi-Hat Rolls (32nd note runs, sustained sub)
/// - Phase 4 (25.6-32.0s): Full Spectrum Climax & Smooth Fade-Out
SceneSignalRecording createDynamicShowcaseSignalRecording() {
  const framesPerSecond = 30;
  const durationSeconds = 32;
  const sampleCount = durationSeconds * framesPerSecond;
  final random = math.Random(42);
  final bytes = BytesBuilder(copy: false);
  final timeline = <Map<String, Object>>[];
  final impactTrack = _EventTracker();
  final accentTrack = _EventTracker();
  final beatTrack = _EventTracker();
  final flashTrack = _EventTracker();

  var phase = 0.0;
  var bass = 0.0;
  var body = 0.0;
  var spark = 0.0;
  var flow = 0.0;
  final smoothSpectrum = List<double>.filled(31, 0.0);

  const phaseDuration = 32.0 / 5.0; // 6.4s per phase

  for (var i = 0; i < sampleCount; i++) {
    final host = (i * Duration.microsecondsPerSecond / framesPerSecond).round();
    final audioTime = 1000000 + host;
    final t = i / framesPerSecond;

    // 5 phases of 6.4s each
    final phaseIdx = (t / phaseDuration).floor().clamp(0, 4);
    final phaseT = t - (phaseIdx * phaseDuration);

    var music = true;
    var bpm = 128.0;
    var isKick = false;
    var isSnare = false;
    var isHat = false;
    var isBeat = false;
    var kickStrength = 0.0;
    var snareStrength = 0.0;
    var hatStrength = 0.0;
    var beatStrength = 0.0;

    switch (phaseIdx) {
      case 0:
        // Ambient Pads: gentle waves, no kicks
        bpm = 75.0;
        flow = 0.85 + 0.10 * math.sin(t * 0.8);
        body = 0.65 + 0.15 * math.cos(t * 1.2);
        bass = (0.20 + 0.12 * math.sin(t * 1.5)).clamp(0.0, 1.0);
        spark = (0.30 + 0.10 * math.cos(t * 2.3)).clamp(0.0, 1.0);
        break;

      case 1:
        // Build-up & Riser: Snare rolls accelerating, rising filter
        bpm = 110.0 + (phaseT / phaseDuration) * 22.0;
        final hitsPerSec = 2.0 + math.pow(phaseT / phaseDuration, 2) * 14.0;
        final snareCycle = (t * hitsPerSec) % 1.0;
        isSnare = snareCycle < 0.25;
        snareStrength = isSnare ? (0.4 + 0.55 * (phaseT / phaseDuration)) : 0.0;
        bass = (0.25 + 0.20 * (phaseT / phaseDuration)).clamp(0.0, 1.0);
        body = math.max(snareStrength, body * 0.82);
        spark = (0.3 + 0.60 * (phaseT / phaseDuration)).clamp(0.0, 1.0);
        flow = 0.5 + 0.45 * (phaseT / phaseDuration);
        // Tension drop: brief silence at the very end of the build (last 0.4s)
        if (phaseT >= phaseDuration - 0.4) {
          music = false;
        }
        break;

      case 2:
        // THE DROP: 128 BPM 4-on-the-floor EDM
        bpm = 128.0;
        phase += bpm / (60 * framesPerSecond);
        isBeat = phase >= 1.0;
        if (isBeat) phase %= 1.0;
        isKick = isBeat;
        final beatSub = (phase * 4.0).floor() % 4;
        isSnare = isBeat && (beatSub == 1 || beatSub == 3);
        isHat = !isBeat && phase >= 0.45 && phase <= 0.60;

        kickStrength = isKick ? 0.96 : 0.0;
        snareStrength = isSnare ? 0.88 : 0.0;
        hatStrength = isHat ? 0.75 : 0.0;
        beatStrength = isKick ? 0.98 : 0.0;

        bass = math.max(kickStrength, bass * 0.72);
        body = math.max(snareStrength, body * 0.80);
        spark = math.max(hatStrength, spark * 0.70);
        flow = 0.75;
        break;

      case 3:
        // Trap 808 & Fast Hi-Hats: 140 BPM
        bpm = 140.0;
        phase += bpm / (60 * framesPerSecond);
        isBeat = phase >= 1.0;
        if (isBeat) phase %= 1.0;
        final barQuarter = (t * (bpm / 60.0)).floor() % 4;
        isKick = isBeat && (barQuarter == 0 || (barQuarter == 2 && phaseT % 2.0 > 1.0));
        isSnare = isBeat && barQuarter == 2;
        // Fast 1/32 note hi-hat rolls in bursts
        final hatStep = (t * (bpm / 60.0) * 8.0) % 1.0;
        isHat = hatStep < 0.35 && (random.nextDouble() < 0.90);

        kickStrength = isKick ? 0.95 : 0.0;
        snareStrength = isSnare ? 0.85 : 0.0;
        hatStrength = isHat ? 0.80 : 0.0;
        beatStrength = isKick ? 0.92 : (isSnare ? 0.75 : 0.0);

        // Long sustained 808 decay
        bass = math.max(kickStrength, bass * 0.91);
        body = math.max(snareStrength, body * 0.82);
        spark = math.max(hatStrength, spark * 0.72);
        flow = 0.65;
        break;

      case 4:
        // Full Spectrum Climax & Fade-out
        bpm = 130.0;
        phase += bpm / (60 * framesPerSecond);
        isBeat = phase >= 1.0;
        if (isBeat) phase %= 1.0;
        isKick = isBeat;
        kickStrength = isKick ? 0.90 : 0.0;
        beatStrength = isKick ? 0.90 : 0.0;

        final fade = phaseT < (phaseDuration - 1.5)
            ? 1.0
            : (1.0 - (phaseT - (phaseDuration - 1.5)) / 1.5).clamp(0.0, 1.0);
        bass = (math.max(kickStrength, bass * 0.75) * fade).clamp(0.0, 1.0);
        body = (0.75 * fade).clamp(0.0, 1.0);
        spark = (0.80 * fade).clamp(0.0, 1.0);
        flow = (0.80 * fade).clamp(0.0, 1.0);
        if (fade <= 0.01) music = false;
        break;
    }

    final energy = music ? (0.2 * bass + 0.3 * body + 0.25 * spark + 0.25 * flow).clamp(0.0, 1.0) : 0.0;

    final impact = impactTrack.sample(kickStrength, audioTime, SceneRenderSignalEventBandV2.low);
    final accent = accentTrack.sample(snareStrength > 0 ? snareStrength : hatStrength, audioTime,
        snareStrength > 0 ? SceneRenderSignalEventBandV2.body : SceneRenderSignalEventBandV2.high);
    final beatEvent = beatTrack.sample(beatStrength, audioTime, SceneRenderSignalEventBandV2.broadband);
    final flash = flashTrack.sample(
        phaseIdx == 2 && isKick ? 0.95 : 0.0, audioTime, SceneRenderSignalEventBandV2.broadband);

    final spectrum = List<double>.generate(31, (band) {
      if (!music) return 0.0;
      final low = math.exp(-math.pow((band - 2.5) / 3.8, 2)) * bass;
      final mid = math.exp(-math.pow((band - 12.0) / 6.0, 2)) * body;
      final high = math.exp(-math.pow((band - 25.0) / 5.0, 2)) * spark;
      final sweepMod = phaseIdx == 1 ? (band <= (phaseT / 8.0) * 30.0 ? 1.0 : 0.15) : 1.0;
      return ((low + mid + high) * sweepMod * (0.85 + 0.15 * math.sin(band * 0.5 + t))).clamp(0.0, 1.0);
    }, growable: false);

    for (var b = 0; b < 31; b++) {
      if (music) {
        final target = spectrum[b];
        // Fast attack, natural exponential release
        smoothSpectrum[b] = target > smoothSpectrum[b]
            ? smoothSpectrum[b] + (target - smoothSpectrum[b]) * 0.65
            : smoothSpectrum[b] * 0.85;
      } else {
        smoothSpectrum[b] = 0.0;
      }
    }

    final frame = SceneRenderSignalFrameV2(
      sessionId: 1,
      sequence: i + 1,
      audioTimestampMicros: audioTime,
      available: true,
      fresh: true,
      musicActive: music,
      dynamics: [energy, energy, math.max(kickStrength, snareStrength), flow, energy, music ? 18.0 : 0.0],
      channels: [bass, body, spark, flow],
      spectrumSummary: [energy, bass, body, flow, spark, math.max(snareStrength, hatStrength), energy * 0.3],
      instantSpectrum: spectrum,
      smoothedSpectrum: smoothSpectrum,
      semantics: [phaseIdx.toDouble(), 0, music ? 0.85 : 0, music ? 0.9 : 0, energy, 0],
      rhythm: [music ? bpm : 0, phase, music ? 0.85 : 0, music ? 0.75 : 0],
      onsets: [kickStrength, snareStrength, hatStrength, math.max(kickStrength, snareStrength)],
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
      'qaSessionSeed': 26,
      'authoredFramesPerSecond': framesPerSecond,
      'observedFramesPerSecond': framesPerSecond,
      'samples': timeline,
    }),
    synthetic: true,
  );
}

/// 2. EDM & Club Drop (24 seconds @ 128 BPM).
/// Heavy 4-on-the-floor kicks, powerful sub-bass peaks and sizzle hi-hats.
SceneSignalRecording createEdmClubDropSignalRecording() {
  const framesPerSecond = 30;
  const sampleCount = 24 * framesPerSecond;
  final bytes = BytesBuilder(copy: false);
  final timeline = <Map<String, Object>>[];
  final impactTrack = _EventTracker();
  final accentTrack = _EventTracker();
  final beatTrack = _EventTracker();
  final flashTrack = _EventTracker();

  var phase = 0.0;
  var bass = 0.0;
  var body = 0.0;
  var spark = 0.0;
  const bpm = 128.0;
  final smoothSpectrum = List<double>.filled(31, 0.0);

  for (var i = 0; i < sampleCount; i++) {
    final host = (i * Duration.microsecondsPerSecond / framesPerSecond).round();
    final audioTime = 1000000 + host;
    final t = i / framesPerSecond;

    // 1-second drop pause at t=11s
    final isDropPause = t >= 11.0 && t < 12.0;
    final music = !isDropPause;

    phase += bpm / (60 * framesPerSecond);
    final isBeat = phase >= 1.0;
    if (isBeat) phase %= 1.0;

    final quarter = (t * (bpm / 60.0)).floor() % 4;
    final isKick = music && isBeat;
    final isSnare = music && isBeat && (quarter == 1 || quarter == 3);
    final isHat = music && !isBeat && phase >= 0.45 && phase <= 0.60;

    final kickStrength = isKick ? 0.98 : 0.0;
    final snareStrength = isSnare ? 0.90 : 0.0;
    final hatStrength = isHat ? 0.80 : 0.0;

    bass = music ? math.max(kickStrength, bass * 0.72) : 0.0;
    body = music ? math.max(snareStrength, body * 0.78) : 0.0;
    spark = music ? math.max(hatStrength, spark * 0.68) : 0.0;
    const flow = 0.78;
    final energy = music ? (0.45 * bass + 0.3 * body + 0.25 * spark).clamp(0.0, 1.0) : 0.0;

    final impact = impactTrack.sample(kickStrength, audioTime, SceneRenderSignalEventBandV2.low);
    final accent = accentTrack.sample(snareStrength, audioTime, SceneRenderSignalEventBandV2.body);
    final beatEvent = beatTrack.sample(kickStrength, audioTime, SceneRenderSignalEventBandV2.broadband);
    final flash = flashTrack.sample(isKick ? 0.95 : 0.0, audioTime, SceneRenderSignalEventBandV2.broadband);

    final spectrum = List<double>.generate(31, (band) {
      if (!music) return 0.0;
      final low = math.exp(-math.pow((band - 2.0) / 3.5, 2)) * bass * 1.1;
      final mid = math.exp(-math.pow((band - 11.0) / 5.5, 2)) * body;
      final high = math.exp(-math.pow((band - 24.0) / 4.5, 2)) * spark;
      return (low + mid + high).clamp(0.0, 1.0);
    }, growable: false);

    for (var b = 0; b < 31; b++) {
      if (music) {
        final target = spectrum[b];
        smoothSpectrum[b] = target > smoothSpectrum[b]
            ? smoothSpectrum[b] + (target - smoothSpectrum[b]) * 0.70
            : smoothSpectrum[b] * 0.85;
      } else {
        smoothSpectrum[b] = 0.0;
      }
    }

    final frame = SceneRenderSignalFrameV2(
      sessionId: 1,
      sequence: i + 1,
      audioTimestampMicros: audioTime,
      available: true,
      fresh: true,
      musicActive: music,
      dynamics: [energy, energy, kickStrength, flow, energy, music ? 18.0 : 0.0],
      channels: [bass, body, spark, flow],
      spectrumSummary: [energy, bass, body, flow, spark, snareStrength, energy * 0.3],
      instantSpectrum: spectrum,
      smoothedSpectrum: smoothSpectrum,
      semantics: [0, 0, music ? 0.9 : 0, music ? 0.95 : 0, energy, 0],
      rhythm: [music ? bpm : 0, phase, music ? 0.95 : 0, music ? 0.85 : 0],
      onsets: [kickStrength, snareStrength, hatStrength, kickStrength],
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
      'qaSessionSeed': 26,
      'authoredFramesPerSecond': framesPerSecond,
      'observedFramesPerSecond': framesPerSecond,
      'samples': timeline,
    }),
    synthetic: true,
  );
}

/// 3. Trap 808 & Fast Hi-Hats (24 seconds @ 140 BPM).
/// Sub-bass 808 rumble with slow decay, 1/32 hi-hat rolls in highs, dry claps.
SceneSignalRecording createTrap808SignalRecording() {
  const framesPerSecond = 30;
  const sampleCount = 24 * framesPerSecond;
  final random = math.Random(140);
  final bytes = BytesBuilder(copy: false);
  final timeline = <Map<String, Object>>[];
  final impactTrack = _EventTracker();
  final accentTrack = _EventTracker();
  final beatTrack = _EventTracker();
  final flashTrack = _EventTracker();

  var phase = 0.0;
  var bass = 0.0;
  var body = 0.0;
  var spark = 0.0;
  const bpm = 140.0;
  final smoothSpectrum = List<double>.filled(31, 0.0);

  for (var i = 0; i < sampleCount; i++) {
    final host = (i * Duration.microsecondsPerSecond / framesPerSecond).round();
    final audioTime = 1000000 + host;
    final t = i / framesPerSecond;

    phase += bpm / (60 * framesPerSecond);
    final isBeat = phase >= 1.0;
    if (isBeat) phase %= 1.0;

    final quarter = (t * (bpm / 60.0)).floor() % 4;
    final isKick = isBeat && (quarter == 0 || (quarter == 2 && t % 2.0 > 1.0));
    final isSnare = isBeat && quarter == 2;
    // 32nd note hi-hat rolls
    final isHat = ((t * (bpm / 60.0) * 8.0) % 1.0) < 0.40 && random.nextDouble() < 0.90;

    final kickStrength = isKick ? 0.95 : 0.0;
    final snareStrength = isSnare ? 0.85 : 0.0;
    final hatStrength = isHat ? 0.88 : 0.0;

    // Resonant 808 sustained sub decay
    bass = math.max(kickStrength, bass * 0.92);
    body = math.max(snareStrength, body * 0.80);
    spark = math.max(hatStrength, spark * 0.70);
    const flow = 0.65;
    final energy = (0.5 * bass + 0.25 * body + 0.25 * spark).clamp(0.0, 1.0);

    final impact = impactTrack.sample(kickStrength, audioTime, SceneRenderSignalEventBandV2.low);
    final accent = accentTrack.sample(snareStrength > 0 ? snareStrength : hatStrength, audioTime,
        snareStrength > 0 ? SceneRenderSignalEventBandV2.body : SceneRenderSignalEventBandV2.high);
    final beatEvent = beatTrack.sample(isKick ? 0.92 : 0.0, audioTime, SceneRenderSignalEventBandV2.broadband);
    final flash = flashTrack.sample(0.0, audioTime, SceneRenderSignalEventBandV2.none);

    final spectrum = List<double>.generate(31, (band) {
      // 808 peaks in ultra-low bands 0, 1, 2
      final sub = math.exp(-math.pow(band / 2.2, 2)) * bass * 1.15;
      final clap = math.exp(-math.pow((band - 13.0) / 4.0, 2)) * body;
      final rolls = math.exp(-math.pow((band - 26.0) / 3.5, 2)) * spark;
      return (sub + clap + rolls).clamp(0.0, 1.0);
    }, growable: false);

    for (var b = 0; b < 31; b++) {
      final target = spectrum[b];
      smoothSpectrum[b] = target > smoothSpectrum[b]
          ? smoothSpectrum[b] + (target - smoothSpectrum[b]) * 0.65
          : smoothSpectrum[b] * 0.86;
    }

    final frame = SceneRenderSignalFrameV2(
      sessionId: 1,
      sequence: i + 1,
      audioTimestampMicros: audioTime,
      available: true,
      fresh: true,
      musicActive: true,
      dynamics: [energy, energy, kickStrength, flow, energy, 18.0],
      channels: [bass, body, spark, flow],
      spectrumSummary: [energy, bass, body, flow, spark, snareStrength, energy * 0.3],
      instantSpectrum: spectrum,
      smoothedSpectrum: smoothSpectrum,
      semantics: [0, 0, 0.85, 0.9, energy, 0],
      rhythm: [bpm, phase, 0.85, 0.75],
      onsets: [kickStrength, snareStrength, hatStrength, kickStrength],
      tonalAvailable: true,
      tonal: [flow, 0.5, 0],
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

/// 4. Ambient & Chillout (24 seconds @ 75 BPM).
/// Soft harmonic pads, organic swells, zero harsh percussive hits.
SceneSignalRecording createAmbientChilloutSignalRecording() {
  const framesPerSecond = 30;
  const sampleCount = 24 * framesPerSecond;
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

    final swell = 0.55 + 0.25 * math.sin(t * 0.9);
    final bass = (0.22 + 0.12 * math.sin(t * 1.4)).clamp(0.0, 1.0);
    final body = (0.70 * swell).clamp(0.0, 1.0);
    final spark = (0.35 + 0.15 * math.cos(t * 1.8)).clamp(0.0, 1.0);
    final flow = swell;
    final energy = swell;

    final impact = impactTrack.sample(0.0, audioTime, SceneRenderSignalEventBandV2.none);
    final accent = accentTrack.sample(0.0, audioTime, SceneRenderSignalEventBandV2.none);
    final beatEvent = beatTrack.sample(0.0, audioTime, SceneRenderSignalEventBandV2.none);
    final flash = flashTrack.sample(0.0, audioTime, SceneRenderSignalEventBandV2.none);

    final spectrum = List<double>.generate(31, (band) {
      final midPeak = math.exp(-math.pow((band - 12.0) / 6.5, 2)) * body;
      final air = math.exp(-math.pow((band - 22.0) / 6.0, 2)) * spark * 0.8;
      final warmth = math.exp(-math.pow((band - 3.0) / 4.0, 2)) * bass;
      return (midPeak + air + warmth).clamp(0.0, 1.0);
    }, growable: false);

    for (var b = 0; b < 31; b++) {
      smoothSpectrum[b] += (spectrum[b] - smoothSpectrum[b]) * 0.25;
    }

    final frame = SceneRenderSignalFrameV2(
      sessionId: 1,
      sequence: i + 1,
      audioTimestampMicros: audioTime,
      available: true,
      fresh: true,
      musicActive: true,
      dynamics: [energy, energy, 0.0, flow, energy, 18.0],
      channels: [bass, body, spark, flow],
      spectrumSummary: [energy, bass, body, flow, spark, 0.0, energy * 0.3],
      instantSpectrum: spectrum,
      smoothedSpectrum: smoothSpectrum,
      semantics: [0, 0, 0.9, 0.95, energy, 0],
      rhythm: [75.0, (t * 75.0 / 60.0) % 1.0, 0.5, 0.8],
      onsets: [0.0, 0.0, 0.0, 0.0],
      tonalAvailable: true,
      tonal: [flow, 0.7, 0],
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
