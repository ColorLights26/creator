import 'dart:convert';
import 'dart:typed_data';

import 'package:audiovisual_creator/probe/energy_probe_identity.dart';
import 'package:audiovisual_creator/probe/energy_probe_loud_signal.dart';
import 'package:audiovisual_creator/probe/energy_probe_profile.dart';
import 'package:audiovisual_creator/probe/energy_probe_record.dart';
import 'package:audiovisual_creator/probe/energy_probe_spec.dart';
import 'package:audiovisual_creator/team_review/visual_revision.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_compositor/authoring.dart';
import 'package:visual_contract/visual_contract.dart';

const _galaxy = CreatorVisualDefinition(
  id: 'galaxia',
  name: 'Galaxia',
  nativeSource:
      'class Visual final : public Scene { float turn = f.delta * f.speed; };',
  nativeBuild: {'hash': 'abc123'},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  modifiers: [
    CreatorModifier.steps('brazos', 'Brazos', min: 2, max: 6, value: 4),
    CreatorModifier.slider(
      'grosor',
      'Grosor',
      min: .004,
      max: .02,
      value: .004,
    ),
    CreatorModifier.toggle('nucleo', 'Núcleo', value: true),
    CreatorModifier.choice(
      'estilo',
      'Estilo',
      options: ['Auto', 'Nítido', 'Nebuloso'],
    ),
  ],
  variations: [
    CreatorVariation('Tormenta', {
      'brazos': 6,
      'estilo': 'Nebuloso',
      'speed': 1.4,
    }),
  ],
);

const _aurora = CreatorVisualDefinition(
  id: 'aurora',
  name: 'Aurora',
  shaderSource: 'float4 paintVisual() { return float4(0); }',
);

const _unhashed = CreatorVisualDefinition(
  id: 'sin_hash',
  name: 'Sin hash',
  nativeSource: 'class Visual final : public Scene {};',
);

Map<Object?, Object?> _surface({
  String sceneId = 'creator_galaxia',
  String session = 's1',
  Object? revision = 'r1',
  int generation = 1,
  int frames = 0,
  double time = 100,
  int gpuFrames = 0,
  double gpuMs = 0,
  double? gpuTime,
  String? timing = 'metal_command_buffer',
  String? backend = 'one_pass_gpu',
  bool preparing = false,
  List<Object?>? programs,
}) => {
  'sceneId': sceneId,
  'sessionId': session,
  'rendererRevision': revision,
  'publishedFrameCount': frames,
  'sampleTimeSeconds': time,
  'generation': generation,
  if (backend != null) 'backendClass': backend,
  'gpuCompletedFrameCount': gpuFrames,
  'gpuTotalTimeMs': gpuMs,
  'gpuLastFrameTimeMs': 1.0,
  'gpuSampleTimeSeconds': gpuTime ?? time,
  if (timing != null) 'gpuTimingSource': timing,
  'preparing': preparing,
  'playing': true,
  'videoSources': <Object?>[],
  'creatorPrograms':
      programs ??
      [
        {
          'programId': 'creator_galaxia',
          'instance': 'i1',
          'updates': frames,
          'simulationAverageMicros': 100.0,
          'framesPerSecond': 30,
          'thermalState': 0,
          'lowPowerMode': false,
        },
      ],
};

Map<Object?, Object?> _device({String thermal = 'nominal'}) => {
  'thermalState': thermal,
  'lowPowerMode': false,
  'batteryLevel': 0.8,
  'batteryState': 'unplugged',
  'charging': false,
  'displayHz': 60,
  'model': 'iPhone15,2',
  'systemName': 'iOS',
  'systemVersion': '26.0',
  'isPhysical': true,
  'memoryBytes': 150 * 1024 * 1024,
};

const _viewport = {
  'logicalWidth': 393.0,
  'logicalHeight': 852.0,
  'devicePixelRatio': 3.0,
};

void main() {
  group('spec', () {
    test('baseline has no visual', () {
      final spec = parseEnergyProbeSpec('baseline');
      expect(spec.baseline, isTrue);
      expect(spec.visualId, isNull);
      expect(spec.text, 'baseline');
      expect(spec.profile, EnergyProbeProfileKind.initial);
    });

    test('a bare id plays the initial values', () {
      final spec = parseEnergyProbeSpec(' galaxia ');
      expect(spec.baseline, isFalse);
      expect(spec.visualId, 'galaxia');
      expect(spec.text, 'galaxia');
      expect(spec.profile, EnergyProbeProfileKind.initial);
      expect(spec.variationIndex, isNull);
    });

    test('@max and @variation=<i>', () {
      final max = parseEnergyProbeSpec('galaxia@max');
      expect(max.visualId, 'galaxia');
      expect(max.profile, EnergyProbeProfileKind.max);
      expect(max.text, 'galaxia@max');
      final variation = parseEnergyProbeSpec('galaxia@variation=2');
      expect(variation.visualId, 'galaxia');
      expect(variation.profile, EnergyProbeProfileKind.variation);
      expect(variation.variationIndex, 2);
    });

    test('profile labels match the record names', () {
      expect(EnergyProbeProfileKind.initial.label, 'default');
      expect(EnergyProbeProfileKind.max.label, 'max');
      expect(EnergyProbeProfileKind.variation.label, 'variation');
    });

    test('rejects malformed specs', () {
      for (final bad in [
        '',
        '   ',
        'Galaxia',
        '1galaxia',
        'galaxia@',
        'galaxia@bar',
        'galaxia@variation',
        'galaxia@variation=',
        'galaxia@variation=x',
        'galaxia@variation=-1',
        'galaxia@max@max',
        'baseline@max',
        'baseline@variation=0',
      ]) {
        expect(
          () => parseEnergyProbeSpec(bad),
          throwsFormatException,
          reason: bad,
        );
      }
    });
  });

  group('launch arguments', () {
    test('reads the option with a separate or an attached value', () {
      expect(
        energyProbeSpecFromArguments([
          '/app/Runner',
          '--colorlights-qa-scene',
          'energy-probe=galaxia@max',
        ]),
        'galaxia@max',
      );
      expect(
        energyProbeSpecFromArguments([
          '--colorlights-qa-scene=energy-probe=baseline',
        ]),
        'baseline',
      );
    });

    test('anything else is not a probe', () {
      expect(energyProbeSpecFromArguments(const []), isNull);
      expect(energyProbeSpecFromArguments(['/app/Runner']), isNull);
      expect(energyProbeSpecFromArguments(['--colorlights-qa-scene']), isNull);
      expect(
        energyProbeSpecFromArguments(['--colorlights-qa-scene', 'scene-lab']),
        isNull,
      );
    });
  });

  group('profile', () {
    test('default is the author\'s initial values', () {
      final profile = resolveEnergyProbeProfile(
        _galaxy,
        parseEnergyProbeSpec('galaxia'),
      );
      expect(profile.kind, EnergyProbeProfileKind.initial);
      expect(profile.variation, isNull);
      expect(profile.controls.toMap(), _galaxy.controls.toMap());
      expect(profile.modifiers, {
        'brazos': 4.0,
        'grosor': .004,
        'nucleo': 1.0,
        'estilo': 0.0,
      });
      expect(profile.toMap()['name'], 'default');
    });

    test('max is the loud basics and every modifier at its upper value', () {
      final profile = resolveEnergyProbeProfile(
        _galaxy,
        parseEnergyProbeSpec('galaxia@max'),
      );
      expect(profile.controls.toMap(), {
        'intensity': 2.0,
        'speed': 1.0,
        'detail': 2.0,
        'glow': 2.0,
      });
      expect(profile.modifiers, {
        'brazos': 6.0,
        'grosor': .02,
        'nucleo': 1.0,
        'estilo': 2.0,
      });
      for (final modifier in _galaxy.modifiers) {
        expect(modifier.accepts(profile.modifiers[modifier.id]!), isTrue);
      }
      expect(_galaxy.resolveModifiers(profile.modifiers), profile.modifiers);
      expect(profile.toMap(), {
        'name': 'max',
        'variation': null,
        'controls': profile.controls.toMap(),
        'modifiers': profile.modifiers,
      });
    });

    test('variation resolves the author\'s look over the initial values', () {
      final profile = resolveEnergyProbeProfile(
        _galaxy,
        parseEnergyProbeSpec('galaxia@variation=0'),
      );
      expect(profile.kind, EnergyProbeProfileKind.variation);
      expect(profile.variation, 'Tormenta');
      expect(profile.controls.toMap(), {
        'intensity': 1.0,
        'speed': 1.4,
        'detail': 1.0,
        'glow': 1.0,
      });
      expect(profile.modifiers, {
        'brazos': 6.0,
        'grosor': .004,
        'nucleo': 1.0,
        'estilo': 2.0,
      });
      expect(profile.toMap()['variation'], 'Tormenta');
    });

    test('a variation the visual lacks is an error', () {
      expect(
        () => resolveEnergyProbeProfile(
          _galaxy,
          parseEnergyProbeSpec('galaxia@variation=1'),
        ),
        throwsFormatException,
      );
      expect(
        () => resolveEnergyProbeProfile(
          _aurora,
          parseEnergyProbeSpec('aurora@variation=0'),
        ),
        throwsFormatException,
      );
    });

    test('max of a visual without modifiers sends none', () {
      final profile = resolveEnergyProbeProfile(
        _aurora,
        parseEnergyProbeSpec('aurora@max'),
      );
      expect(profile.modifiers, isEmpty);
      expect(profile.controls.toMap()['intensity'], 2.0);
    });
  });

  group('loud signal', () {
    final recording = createSyntheticSceneSignalRecording();
    final loud = EnergyProbeLoudSignal.fromRecording(recording);

    test('the harness byte offsets map to the amplified Dart fields', () {
      // `for (o = 40; o < 356; o += 4) if (o != 60)` covers dynamics[0..4],
      // channels, spectrumSummary, instantSpectrum and smoothedSpectrum.
      expect(SceneRenderSignalFrameV2.floatBlockOffset, 40);
      expect(
        (356 - 40) ~/ 4,
        SceneRenderSignalFrameV2.dynamicsFieldCount +
            SceneRenderSignalFrameV2.channelsFieldCount +
            SceneRenderSignalFrameV2.spectrumSummaryFieldCount +
            SceneRenderSignalFrameV2.spectrumBandCount * 2,
      );
      expect((60 - 40) ~/ 4, energyProbeAmplifiedDynamics);
      // Events at 424 with stride 24: impact, accent, beat, flash.
      expect(SceneRenderSignalFrameV2.eventBlockOffset, 424);
      expect(SceneRenderSignalFrameV2.eventStride, 24);
    });

    test('plays the first contiguous loud section only', () {
      // Music starts at t = 1 s (frame 30) and stops at t = 14 s (frame 420).
      expect(loud.firstIndex, 30);
      expect(loud.length, 390);
      expect(loud.frames.first.sequence, 31);
      expect(loud.frames.last.sequence, 420);
      expect(loud.frames.every(energyProbeFrameActive), isTrue);
      expect(
        energyProbeFrameActive(recording.samples[loud.firstIndex - 1].frame),
        isFalse,
      );
      expect(
        energyProbeFrameActive(
          recording.samples[loud.firstIndex + loud.length].frame,
        ),
        isFalse,
      );
      expect(loud.sessionId, recording.samples.first.frame.sessionId);
    });

    test('every active hit has full strength and each beat flashes', () {
      var beats = 0;
      for (var i = 0; i < loud.length; i++) {
        final source = recording.samples[loud.firstIndex + i].frame;
        final frame = loud.frames[i];
        for (final (before, after) in [
          (source.impact, frame.impact),
          (source.accent, frame.accent),
          (source.beat, frame.beat),
        ]) {
          expect(after.active, before.active);
          expect(after.serial, before.serial);
          expect(after.timestampMicros, before.timestampMicros);
          expect(after.band, before.band);
          expect(after.strength, before.active ? 1.0 : before.strength);
        }
        // The synthetic flash track never fires, so a beat always flashes.
        expect(source.flash.active, isFalse);
        if (source.beat.active) {
          beats++;
          expect(frame.flash.active, isTrue);
          expect(frame.flash.serial, source.beat.serial);
          expect(frame.flash.timestampMicros, source.beat.timestampMicros);
          expect(frame.flash.band, source.beat.band);
          expect(frame.flash.strength, 1.0);
        } else {
          expect(frame.flash.active, isFalse);
          expect(frame.flash.serial, source.flash.serial);
          expect(frame.flash.strength, source.flash.strength);
        }
      }
      expect(beats, greaterThan(10));
    });

    test('active frames are amplified x1.35 and clamped; the rest is kept', () {
      double amplified(double value) => (value * 1.35).clamp(0.0, 1.0);
      var clamped = 0;
      for (var i = 0; i < loud.length; i++) {
        final source = recording.samples[loud.firstIndex + i].frame;
        final frame = loud.frames[i];
        for (var d = 0; d < 5; d++) {
          expect(
            frame.dynamics[d],
            closeTo(amplified(source.dynamics[d]), 1e-9),
          );
        }
        expect(frame.dynamics[5], source.dynamics[5]);
        for (final (before, after) in [
          (source.channels, frame.channels),
          (source.spectrumSummary, frame.spectrumSummary),
          (source.instantSpectrum, frame.instantSpectrum),
          (source.smoothedSpectrum, frame.smoothedSpectrum),
        ]) {
          for (var k = 0; k < before.length; k++) {
            expect(after[k], closeTo(amplified(before[k]), 1e-9));
            if (before[k] * 1.35 > 1) clamped++;
          }
        }
        expect(frame.semantics, source.semantics);
        expect(frame.rhythm, source.rhythm);
        expect(frame.onsets, source.onsets);
        expect(frame.tonal, source.tonal);
        expect(frame.tonalAvailable, source.tonalAvailable);
        expect(frame.sessionId, source.sessionId);
        expect(frame.sequence, source.sequence);
        expect(frame.audioTimestampMicros, source.audioTimestampMicros);
        expect(frame.available, source.available);
        expect(frame.fresh, source.fresh);
        expect(frame.musicActive, source.musicActive);
      }
      expect(clamped, greaterThan(0), reason: 'the gain must hit the clamp');
    });

    test('an inactive frame keeps its levels', () {
      final source = recording.samples.first.frame;
      expect(energyProbeFrameActive(source), isFalse);
      final frame = loudSignalFrame(source);
      expect(frame.dynamics, source.dynamics);
      expect(frame.channels, source.channels);
      expect(frame.instantSpectrum, source.instantSpectrum);
      expect(frame.smoothedSpectrum, source.smoothedSpectrum);
      expect(frame.toBytes(), source.toBytes());
    });

    test('an active frame with an active flash keeps its own flash', () {
      final source = loud.frames.firstWhere((f) => f.beat.active);
      final flashed = SceneRenderSignalFrameV2(
        sessionId: source.sessionId,
        sequence: source.sequence,
        audioTimestampMicros: source.audioTimestampMicros,
        available: true,
        fresh: true,
        musicActive: true,
        dynamics: source.dynamics,
        channels: source.channels,
        spectrumSummary: source.spectrumSummary,
        instantSpectrum: source.instantSpectrum,
        smoothedSpectrum: source.smoothedSpectrum,
        semantics: source.semantics,
        rhythm: source.rhythm,
        onsets: source.onsets,
        tonalAvailable: source.tonalAvailable,
        tonal: source.tonal,
        impact: source.impact,
        accent: source.accent,
        beat: source.beat,
        flash: const SceneRenderSignalEventV2(
          serial: 77,
          active: true,
          timestampMicros: 5,
          strength: .2,
          band: SceneRenderSignalEventBandV2.high,
        ),
      );
      final frame = loudSignalFrame(flashed);
      expect(frame.flash.serial, 77);
      expect(frame.flash.band, SceneRenderSignalEventBandV2.high);
      expect(frame.flash.strength, 1.0);
    });

    test(
      'ticks index the section like the harness and wrap with a new session',
      () {
        final first = loud.frameForTick(0, 30);
        expect(first.index, 0);
        expect(first.cycle, 0);
        expect(first.frame.sessionId, loud.sessionId);
        expect(loud.frameForTick(389, 30).index, 389);
        final wrapped = loud.frameForTick(390, 30);
        expect(wrapped.index, 0);
        expect(wrapped.cycle, 1);
        expect(wrapped.frame.sessionId, loud.sessionId + 1);
        expect(wrapped.frame.sequence, loud.frames.first.sequence);
        expect(loud.frameForTick(780, 30).cycle, 2);
        // A 60 fps visual sees each signal frame on two consecutive ticks.
        expect(loud.frameForTick(0, 60).index, 0);
        expect(loud.frameForTick(1, 60).index, 0);
        expect(loud.frameForTick(2, 60).index, 1);
        expect(loud.frameForTick(779, 60).index, 389);
        expect(loud.frameForTick(780, 60).cycle, 1);
        expect(() => loud.frameForTick(-1, 30), throwsArgumentError);
        expect(() => loud.frameForTick(0, 0), throwsArgumentError);
      },
    );

    test('a recording that never becomes active is rejected', () {
      final silent = SceneSignalRecording.fromBundle(
        signals: Uint8List.fromList([
          for (final sample in recording.samples.take(3))
            ...sample.frame.toSilent().toBytes(),
        ]),
        timelineJson: jsonEncode({
          'formatVersion': 1,
          'kind': 'scene_timeline_reference_v1',
          'qaSessionSeed': 26,
          'authoredFramesPerSecond': 30,
          'observedFramesPerSecond': 30,
          'samples': [
            for (final sample in recording.samples.take(3))
              {
                'hostTimeMicros': sample.hostTime.inMicroseconds,
                'mediaPtsMicros': sample.frame.audioTimestampMicros,
                'eventSerials': {
                  'impact': 0,
                  'accent': 0,
                  'beat': 0,
                  'flash': 0,
                },
              },
          ],
        }),
        synthetic: true,
      );
      expect(
        () => EnergyProbeLoudSignal.fromRecording(silent),
        throwsFormatException,
      );
    });
  });

  group('identity', () {
    test('program hash is the build hash or the shader digest', () {
      expect(energyProbeProgramHash(_galaxy), 'abc123');
      expect(energyProbeProgramHash(_unhashed), isNull);
      expect(
        energyProbeProgramHash(_aurora),
        sha256.convert(utf8.encode(_aurora.shaderSource)).toString(),
      );
    });

    test('build hash comes from the manifest when present', () {
      expect(energyProbeBuildHash('{"hash": "h1"}'), 'h1');
      expect(energyProbeBuildHash(null), isNull);
      expect(energyProbeBuildHash('not json'), isNull);
      expect(energyProbeBuildHash('{"other": 1}'), isNull);
      expect(energyProbeBuildHash('[1]'), isNull);
    });

    test('the creator object names what is measured', () {
      final profile = resolveEnergyProbeProfile(
        _galaxy,
        parseEnergyProbeSpec('galaxia@variation=0'),
      );
      final creator = energyProbeCreatorIdentity(
        visual: _galaxy,
        profile: profile,
        reactive: true,
        seed: _galaxy.seed,
        buildHash: 'b1',
      );
      expect(creator, {
        'visualId': 'galaxia',
        'programId': 'creator_galaxia',
        'kind': 'native',
        'programHash': 'abc123',
        'revision': visualRevision(_galaxy),
        'buildHash': 'b1',
        'profile': profile.toMap(),
        'framesPerSecond': 30,
        'reactive': true,
        'signal': 'synthetic_loud',
        'role': 'background',
        'reactivity': 'optional',
        'seed': 42,
      });
      final shader = energyProbeCreatorIdentity(
        visual: _aurora,
        profile: resolveEnergyProbeProfile(
          _aurora,
          parseEnergyProbeSpec('aurora'),
        ),
        reactive: false,
        seed: 7,
      );
      expect(shader, containsPair('kind', 'shader'));
      // A visual that gets no signal must not claim one.
      expect(shader, containsPair('signal', null));
      expect(shader, containsPair('reactive', false));
      expect(jsonEncode(creator), isA<String>());
    });
  });

  group('record', () {
    EnergyProbeRecorder recorder() => EnergyProbeRecorder(
      visual: 'galaxia@max',
      sceneId: 'creator_galaxia',
      creator: const {'visualId': 'galaxia'},
    );

    test('the first poll has identity but no rates', () {
      final record = recorder().record(
        epochMilliseconds: 1700000000000,
        wallMicros: 2000000,
        processCpuMicros: 100000,
        flutterFrames: 60,
        device: _device(),
        surface: _surface(frames: 100, time: 100),
        viewport: _viewport,
      );
      expect(record['visual'], 'galaxia@max');
      expect(record['sceneId'], 'creator_galaxia');
      expect(record['epochMs'], 1700000000000);
      expect(record['intervalS'], 2.0);
      expect(record['thermal'], 'nominal');
      expect(record['lowPower'], isFalse);
      expect(record['charging'], isFalse);
      expect(record['cpu'], isNull);
      expect(record['memMb'], 150.0);
      expect(record['flutterFps'], 30.0);
      expect(record['displayHz'], 60);
      expect(record['surface'], isTrue);
      expect(record['sessionId'], 's1');
      expect(record['generation'], 1);
      expect(record['backendClass'], 'one_pass_gpu');
      expect(record['gpuTimingSource'], 'metal_command_buffer');
      expect(record['publishedFrames'], 100);
      expect(record['publishedFps'], isNull);
      expect(record['gpuMsPerFrame'], isNull);
      expect(record['gpuFrames'], isNull);
      expect(record['gpuMsPerSecond'], isNull);
      expect(record['energyLevel'], 'best');
      expect(record['energyGovernor'], 'none');
      expect(record['playing'], isTrue);
      expect(record['preparing'], isFalse);
      expect(record['videoSources'], 0);
      expect(record['videosWithFrame'], 0);
      expect(record['pendingMedia'], isFalse);
      expect(record['probeBaseline'], isFalse);
      expect(record['creator'], {'visualId': 'galaxia'});
      expect(record['device'], {
        'model': 'iPhone15,2',
        'systemName': 'iOS',
        'systemVersion': '26.0',
        'isPhysical': true,
        'displayHz': 60,
      });
      expect(record['viewport'], _viewport);
      expect(record.containsKey('error'), isFalse);
      expect(jsonEncode(record), contains('"visual":"galaxia@max"'));
    });

    test('two polls of one session give the rates of the main app', () {
      final probe = recorder();
      probe.record(
        epochMilliseconds: 0,
        wallMicros: 2000000,
        processCpuMicros: 100000,
        flutterFrames: 60,
        device: _device(),
        surface: _surface(frames: 100, time: 100, gpuFrames: 10, gpuMs: 12),
        viewport: _viewport,
      );
      final record = probe.record(
        epochMilliseconds: 2000,
        wallMicros: 4000000,
        processCpuMicros: 600000,
        flutterFrames: 61,
        device: _device(thermal: 'fair'),
        surface: _surface(
          frames: 160,
          time: 102,
          gpuFrames: 70,
          gpuMs: 84,
          gpuTime: 101.99,
        ),
        viewport: _viewport,
      );
      expect(record['intervalS'], 2.0);
      expect(record['cpu'], 25.0);
      expect(record['thermal'], 'fair');
      expect(record['flutterFps'], 30.5);
      expect(record['publishedFps'], 30.0);
      expect(record['gpuFrames'], 60);
      expect(record['gpuMsPerFrame'], 1.2);
      // 1.2 ms x 60 frames over the 2 s between the two sample times.
      expect(record['gpuMsPerSecond'], 36.0);
    });

    test(
      'a changed session, generation, backend or timing source gives null',
      () {
        Map<String, Object?> second(Map<Object?, Object?> next) {
          final probe = recorder();
          probe.record(
            epochMilliseconds: 0,
            wallMicros: 2000000,
            processCpuMicros: 0,
            flutterFrames: 0,
            device: _device(),
            surface: _surface(frames: 100, time: 100, gpuFrames: 10, gpuMs: 12),
            viewport: _viewport,
          );
          return probe.record(
            epochMilliseconds: 2000,
            wallMicros: 4000000,
            processCpuMicros: 0,
            flutterFrames: 0,
            device: _device(),
            surface: next,
            viewport: _viewport,
          );
        }

        final session = second(
          _surface(
            session: 's2',
            frames: 160,
            time: 102,
            gpuFrames: 70,
            gpuMs: 84,
          ),
        );
        expect(session['surface'], isTrue);
        expect(session['publishedFps'], isNull);
        expect(session['gpuMsPerFrame'], isNull);
        expect(session['gpuMsPerSecond'], isNull);

        final generation = second(
          _surface(
            generation: 2,
            frames: 160,
            time: 102,
            gpuFrames: 70,
            gpuMs: 84,
          ),
        );
        expect(generation['publishedFps'], isNull);
        expect(generation['gpuFrames'], isNull);

        final revision = second(
          _surface(
            revision: 'r2',
            frames: 160,
            time: 102,
            gpuFrames: 70,
            gpuMs: 84,
          ),
        );
        expect(revision['publishedFps'], isNull);
        expect(revision['gpuFrames'], isNull);

        // The published rate survives a backend swap; GPU timing does not.
        final backend = second(
          _surface(
            backend: 'scene_surface_ci_gpu',
            frames: 160,
            time: 102,
            gpuFrames: 70,
            gpuMs: 84,
          ),
        );
        expect(backend['publishedFps'], 30.0);
        expect(backend['gpuMsPerFrame'], isNull);

        final timing = second(
          _surface(
            timing: null,
            frames: 160,
            time: 102,
            gpuFrames: 70,
            gpuMs: 84,
          ),
        );
        expect(timing['publishedFps'], 30.0);
        expect(timing['gpuMsPerFrame'], isNull);

        // No new GPU frames or a GPU sample outside the window: null, not 0.
        final stale = second(
          _surface(frames: 160, time: 102, gpuFrames: 10, gpuMs: 12),
        );
        expect(stale['publishedFps'], 30.0);
        expect(stale['gpuFrames'], isNull);
        final outside = second(
          _surface(
            frames: 160,
            time: 102,
            gpuFrames: 70,
            gpuMs: 84,
            gpuTime: 99,
          ),
        );
        expect(outside['gpuFrames'], isNull);

        // A rewound frame counter or an implausible window is not a rate.
        final rewound = second(_surface(frames: 90, time: 102));
        expect(rewound['publishedFps'], isNull);
        final tooLong = second(_surface(frames: 400, time: 110));
        expect(tooLong['publishedFps'], isNull);
      },
    );

    test('the surface of another scene does not count', () {
      final record = recorder().record(
        epochMilliseconds: 0,
        wallMicros: 2000000,
        processCpuMicros: 0,
        flutterFrames: 0,
        device: _device(),
        surface: _surface(sceneId: 'creator_otro'),
        viewport: _viewport,
      );
      expect(record['surface'], isFalse);
      expect(record['sessionId'], isNull);
      expect(record['publishedFrames'], isNull);
      expect(record['playing'], isNull);
    });

    test(
      'preparing is pending media; a visual without music still reports',
      () {
        final record = recorder().record(
          epochMilliseconds: 0,
          wallMicros: 2000000,
          processCpuMicros: 0,
          flutterFrames: 0,
          device: _device(),
          surface: _surface(preparing: true),
          viewport: _viewport,
        );
        expect(record['preparing'], isTrue);
        expect(record['pendingMedia'], isTrue);
      },
    );

    test(
      'without a device snapshot the program metrics name the thermal state',
      () {
        final record = recorder().record(
          epochMilliseconds: 0,
          wallMicros: 2000000,
          processCpuMicros: 0,
          flutterFrames: 0,
          device: null,
          surface: _surface(
            programs: [
              {'thermalState': 2, 'lowPowerMode': true, 'framesPerSecond': 30},
            ],
          ),
          viewport: _viewport,
        );
        expect(record['thermal'], 'serious');
        expect(record['lowPower'], isTrue);
        expect(record['charging'], isNull);
        expect(record['memMb'], isNull);
        expect(record['displayHz'], isNull);
        expect(record['device'], isNull);
      },
    );

    test('thermal names', () {
      expect(energyProbeThermalName(0), 'nominal');
      expect(energyProbeThermalName(3), 'critical');
      expect(energyProbeThermalName(4), isNull);
      expect(energyProbeThermalName('fair'), 'fair');
      expect(energyProbeThermalName('unknown'), isNull);
      expect(energyProbeThermalName(null), isNull);
    });

    test('cpu needs two reads inside a plausible window', () {
      final probe = recorder();
      probe.record(
        epochMilliseconds: 0,
        wallMicros: 2000000,
        processCpuMicros: 100000,
        flutterFrames: 0,
        device: null,
        surface: null,
        viewport: _viewport,
      );
      final missing = probe.record(
        epochMilliseconds: 0,
        wallMicros: 4000000,
        processCpuMicros: null,
        flutterFrames: 0,
        device: null,
        surface: null,
        viewport: _viewport,
      );
      expect(missing['cpu'], isNull);
      final resumed = probe.record(
        epochMilliseconds: 0,
        wallMicros: 6000000,
        processCpuMicros: 300000,
        flutterFrames: 0,
        device: null,
        surface: null,
        viewport: _viewport,
      );
      expect(resumed['cpu'], isNull, reason: 'no previous CPU read');
      final tooLong = probe.record(
        epochMilliseconds: 0,
        wallMicros: 12000000,
        processCpuMicros: 400000,
        flutterFrames: 0,
        device: null,
        surface: null,
        viewport: _viewport,
      );
      expect(tooLong['cpu'], isNull);
      expect(tooLong['intervalS'], 6.0);
    });

    test('the baseline has no scene and says so', () {
      final probe = EnergyProbeRecorder(visual: 'baseline', sceneId: null);
      final record = probe.record(
        epochMilliseconds: 0,
        wallMicros: 2000000,
        processCpuMicros: 0,
        flutterFrames: 120,
        device: _device(),
        surface: _surface(),
        viewport: _viewport,
      );
      expect(record['visual'], 'baseline');
      expect(record['sceneId'], isNull);
      expect(record['probeBaseline'], isTrue);
      expect(record['surface'], isFalse);
      expect(record['creator'], isNull);
      expect(record['flutterFps'], 60.0);
      expect(record['thermal'], 'nominal');
      expect(record['energyLevel'], 'best');
    });

    test('a compositor error travels with the record', () {
      final record = recorder().record(
        epochMilliseconds: 0,
        wallMicros: 2000000,
        processCpuMicros: 0,
        flutterFrames: 0,
        device: _device(),
        surface: null,
        viewport: _viewport,
        error: 'La plantilla cambió.',
      );
      expect(record['error'], 'La plantilla cambió.');
      expect(record['surface'], isFalse);
    });
  });
}
