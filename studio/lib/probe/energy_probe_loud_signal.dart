/// The loud synthetic music of the native energy harness, in Dart. Pure
/// Dart: only the shared wire contract.
///
/// Mirrors `Music::makeLoud` and `struct Loud` in
/// `packages/scene_program_native/test/authored_probe.cpp`: every active hit
/// at full strength, each beat also flashes, the sustained levels of the
/// active frames x1.35 (clamped to 0..1), and only the first contiguous loud
/// section is played, in a loop.
library;

import 'dart:math' as math;

import 'package:visual_contract/visual_contract.dart';

/// Signal frames per second of the recordings the harness indexes with.
const energyProbeSignalRate = 30;

/// Gain applied to the sustained levels of the active frames.
const energyProbeLoudGain = 1.35;

/// Full strength of every active event.
const energyProbeLoudStrength = 1.0;

/// How many leading entries of `dynamics` are amplified (the sixth, at byte
/// offset 60, is left alone by the harness).
const energyProbeAmplifiedDynamics = 5;

/// `available && musicActive`: the flags the harness tests with `& 5`.
bool energyProbeFrameActive(SceneRenderSignalFrameV2 frame) =>
    frame.available && frame.musicActive;

/// One frame made loud exactly as the harness does.
SceneRenderSignalFrameV2 loudSignalFrame(SceneRenderSignalFrameV2 frame) {
  // 1. Every active hit at full strength; a beat without a flash also flashes.
  final beat = frame.beat;
  final flashSource = beat.active && !frame.flash.active ? beat : frame.flash;
  SceneRenderSignalEventV2 loudEvent(SceneRenderSignalEventV2 event) =>
      event.active
          ? SceneRenderSignalEventV2(
            serial: event.serial,
            active: true,
            timestampMicros: event.timestampMicros,
            strength: energyProbeLoudStrength,
            band: event.band,
          )
          : event;

  // 2. The sustained levels of the active frames, amplified and clamped.
  final active = energyProbeFrameActive(frame);
  List<double> amplify(List<double> values, [int? count]) {
    if (!active) return values;
    final limit = count ?? values.length;
    return List<double>.generate(
      values.length,
      (i) =>
          i < limit
              ? math.min(1.0, math.max(0.0, values[i] * energyProbeLoudGain))
              : values[i],
      growable: false,
    );
  }

  return SceneRenderSignalFrameV2(
    sessionId: frame.sessionId,
    sequence: frame.sequence,
    audioTimestampMicros: frame.audioTimestampMicros,
    available: frame.available,
    fresh: frame.fresh,
    musicActive: frame.musicActive,
    dynamics: amplify(frame.dynamics, energyProbeAmplifiedDynamics),
    channels: amplify(frame.channels),
    spectrumSummary: amplify(frame.spectrumSummary),
    instantSpectrum: amplify(frame.instantSpectrum),
    smoothedSpectrum: amplify(frame.smoothedSpectrum),
    semantics: frame.semantics,
    rhythm: frame.rhythm,
    onsets: frame.onsets,
    tonalAvailable: frame.tonalAvailable,
    tonal: frame.tonal,
    impact: loudEvent(frame.impact),
    accent: loudEvent(frame.accent),
    beat: loudEvent(beat),
    flash: loudEvent(flashSource),
  );
}

/// The frame of the loud section due at one app tick.
class EnergyProbeSignalTick {
  const EnergyProbeSignalTick({
    required this.frame,
    required this.index,
    required this.cycle,
  });

  /// Already carries the session id of its [cycle].
  final SceneRenderSignalFrameV2 frame;

  /// Position inside the loud section.
  final int index;

  /// How many times the section has wrapped; 0 on the first pass.
  final int cycle;
}

/// The first contiguous loud section of a recording, looped.
class EnergyProbeLoudSignal {
  EnergyProbeLoudSignal._(this.frames, this.firstIndex);

  /// Loud frames of [recording] from the first active frame after index 0
  /// up to (not including) the first inactive frame that follows. Throws
  /// [FormatException] when the recording never becomes active.
  factory EnergyProbeLoudSignal.fromRecording(SceneSignalRecording recording) {
    final samples = recording.samples;
    var start = 0;
    for (var i = 1; i < samples.length; i++) {
      if (energyProbeFrameActive(samples[i].frame)) {
        start = i;
        break;
      }
    }
    if (start == 0) {
      throw const FormatException(
        'La grabación sintética no tiene música activa.',
      );
    }
    var end = start;
    while (end < samples.length && energyProbeFrameActive(samples[end].frame)) {
      end++;
    }
    return EnergyProbeLoudSignal._(
      List<SceneRenderSignalFrameV2>.unmodifiable([
        for (var i = start; i < end; i++) loudSignalFrame(samples[i].frame),
      ]),
      start,
    );
  }

  /// The loud section, already transformed.
  final List<SceneRenderSignalFrameV2> frames;

  /// Index of the first loud frame in the source recording.
  final int firstIndex;

  int get length => frames.length;

  /// Session id of the recording; each wrap adds the cycle number so the
  /// engine sees a new session, as the studio replay does.
  int get sessionId => frames.first.sessionId;

  /// The signal frame for app tick [tick] of a visual at [framesPerSecond],
  /// indexed as the harness does: `tick * 30 / fps`, wrapped around the
  /// section. A 60 fps visual receives each frame on two consecutive ticks.
  EnergyProbeSignalTick frameForTick(int tick, int framesPerSecond) {
    if (tick < 0 || framesPerSecond <= 0) {
      throw ArgumentError('tick and framesPerSecond must be positive.');
    }
    final position = tick * energyProbeSignalRate ~/ framesPerSecond;
    final cycle = position ~/ length;
    final index = position % length;
    final frame = frames[index];
    return EnergyProbeSignalTick(
      frame: cycle == 0 ? frame : frame.withSessionId(frame.sessionId + cycle),
      index: index,
      cycle: cycle,
    );
  }
}
