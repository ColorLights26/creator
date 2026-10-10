import 'dart:convert';
import 'dart:io';

import 'package:audiovisual_creator/readiness/creator_readiness.dart';
import 'package:audiovisual_creator/team_review/revision_links.dart';
import 'package:audiovisual_creator/team_review/visual_revision.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_compositor/authoring.dart';
import 'package:scene_compositor/creator_build_manifest.dart';
import 'package:scene_compositor/creator_device_card_evidence.dart';
import 'package:scene_compositor/native_compiler.dart';

import '../tool/readiness.dart';
import '../../packages/scene_compositor/test/support/creator_trace_fixture.dart';

/// The readiness tool on a throwaway repo: it parses the real check logs
/// line by line, binds them to a technical identity (build manifest), refuses
/// checks of another build, consumes a DATA copy of the energy contract,
/// verifies a device card only against its own row and log for this exact
/// program, build, device, protocol and cadence, and proposes (never
/// confirms) revision links. Every row, log and contract here is SYNTHETIC.
void main() {
  late Directory repo;
  late Directory catalog;
  late Directory evidence;
  late StringBuffer out;
  late StringBuffer err;

  // The fake catalog must have been compiled by the SDK this package resolves
  // (the tool refuses a catalog of another SDK), so the fixtures carry it.
  final sdk = creatorNativeSdkHash(Directory.current);
  final alpha = CreatorVisualDefinition(
    id: 'alpha',
    name: 'Alpha',
    nativeSource: 'class Visual final : public Scene { int x = m.capas; };',
    nativeBuild: {
      'abi': 1,
      'hash': 'hash-alpha-1',
      'imageHashes': <String, String>{},
      'materials': <String>[],
      'sdkHash': sdk,
    },
    framesPerSecond: 60,
    modifiers: [
      CreatorModifier.steps('capas', 'Capas', min: 1, max: 40, value: 5),
    ],
  );
  const beta = CreatorVisualDefinition(
    id: 'beta',
    name: 'Beta',
    shaderSource: 'vec4 paintVisual() { return vec4(0); }',
    role: CreatorRole.overlay,
  );
  final plasma = CreatorVisualDefinition(
    id: 'plasma_scene',
    name: 'Plasma',
    nativeSource: 'class Visual final : public Scene {};',
    nativeBuild: {
      'abi': 1,
      'hash': 'hash-plasma',
      'imageHashes': <String, String>{},
      'materials': <String>[],
      'sdkHash': sdk,
    },
  );
  final synthwave = CreatorVisualDefinition(
    id: 'synthwave_scene',
    name: 'Synthwave',
    nativeSource: 'class Visual final : public Scene {};',
    nativeBuild: {
      'abi': 1,
      'hash': 'hash-synth',
      'imageHashes': <String, String>{},
      'materials': <String>[],
      'sdkHash': sdk,
    },
  );

  void writeCatalog(List<CreatorVisualDefinition> visuals) {
    final sorted = [...visuals]..sort((a, b) => a.id.compareTo(b.id));
    File('${catalog.path}/assets/creator_catalog.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'schemaVersion': 1,
          'visuals': [for (final v in sorted) v.toManifest()],
        }),
      );
    File('${catalog.path}/assets/catalog_metadata.json').writeAsStringSync(
      jsonEncode({
        'schemaVersion': 1,
        'visuals': [for (final v in sorted) v.toMetadata()],
      }),
    );
  }

  // The fake repo's runtime: the manifest hashes every SceneCatalog*.swift,
  // the signal frame and the allocator class of the image surface.
  void writeEngine({String runtime = 'swift v1', String checks = 't1'}) {
    final files = {
      'packages/scene_compositor/ios/Classes/Runtime/SceneCatalogCreatorScene.swift':
          runtime,
      'packages/scene_compositor/ios/Classes/Runtime/SceneRenderSignalFrameV2.swift':
          'signal',
      'packages/scene_compositor/ios/Classes/Runtime/SceneRenderV2ImageSurface.swift':
          'surface\n@available(iOS 15.0, *)\nfinal class SceneSurfaceNativeOutputAllocator {\n  let stub = 1\n}\n',
      'packages/scene_compositor/ios/Tests/creator_scene_tests.swift': checks,
      'packages/scene_compositor/ios/Tests/check_creator_scenes.py': 't2',
      'packages/scene_compositor/ios/Tests/creator_catalog_tests.swift': 't3',
      'packages/scene_compositor/ios/Tests/check_creator_catalog.rb': 't4',
      'packages/scene_program_native/test/authored_probe.cpp': 't5',
      'packages/scene_program_native/test/check_native.py': 't6',
      'packages/scene_program_native/test/runtime_test.cpp': 't7',
    };
    for (final entry in files.entries) {
      File('${repo.path}/${entry.key}')
        ..createSync(recursive: true)
        ..writeAsStringSync(entry.value);
    }
    for (final path in creatorBuildInputPaths) {
      File('${repo.path}/$path')
        ..createSync(recursive: true)
        ..writeAsStringSync('fixture $path');
    }
    Directory('${repo.path}/studio').createSync(recursive: true);
  }

  /// The build hash the tool computes for the fake repo (its SDK and
  /// material compiler come from this resolved package, like the tool's).
  String buildHash() =>
      creatorBuildManifest(
            repo: repo,
            host: Directory.current,
            catalog: catalog,
          )['hash']
          as String;

  String catalogSha() =>
      sha256
          .convert(
            File(
              '${catalog.path}/assets/creator_catalog.json',
            ).readAsBytesSync(),
          )
          .toString();

  void writeChecks({String nativeExtra = '', bool shaders = true}) {
    final checks = Directory('${evidence.path}/checks')
      ..createSync(recursive: true);
    File('${checks.path}/check_native_strict.log').writeAsStringSync(
      'PASS authored CPU creator_alpha: independent instances, repeatable state, 30/60 FPS, 120 command bytes\n'
      'PASS modifiers creator_alpha: extremes, options, variations, live change, 30/60 FPS\n'
      'WARN passes creator_alpha: 30 pasadas con todos los ajustes al máximo (máx 28 en iPad)\n'
      'PASS passes creator_alpha: iPhone 3 (máx 35), iPad 3 (máx 28)\n'
      'PASS authored CPU creator_plasma_scene: independent instances, repeatable state, 30/60 FPS, 8 command bytes\n'
      'PASS passes creator_plasma_scene: iPhone 1 (máx 35), iPad 1 (máx 28)\n'
      'PASS authored CPU creator_synthwave_scene: independent instances, repeatable state, 30/60 FPS, 8 command bytes\n'
      'PASS passes creator_synthwave_scene: iPhone 2 (máx 35), iPad 2 (máx 28)\n'
      '$nativeExtra',
    );
    File('${checks.path}/check_native_pass_report.log').writeAsStringSync(
      'PASSES creator_alpha fps 60 iPhone 3 11473920 iPad 3 13996800\n',
    );
    File('${checks.path}/check_creator_scenes.log').writeAsStringSync(
      'PASS continuity creator_alpha: resize, controls, reaction, rollback and seed reset\n'
      'PASS authored creator_alpha: native Metal scene, alpha and state replay\n'
      'PASS behavior creator_alpha: optional, identical-history musical/neutral probes\n'
      'PASS authored creator_plasma_scene: native Metal scene, alpha and state replay\n'
      'PASS behavior creator_plasma_scene: optional, identical-history musical/neutral probes\n'
      'PASS authored creator_synthwave_scene: native Metal scene, alpha and state replay\n'
      'PASS behavior creator_synthwave_scene: optional, identical-history musical/neutral probes\n',
    );
    File('${checks.path}/check_creator_catalog.log').writeAsStringSync(
      shaders
          ? 'PASS authored creator_beta: 192x128, 24576 visible pixels, 3278 distinct BGRA values\n'
              'PASS behavior creator_beta: optional, synthetic same-time music/silence/unavailable/off probes\n'
          : 'Creator native tests failed to compile\n',
    );
    File('${checks.path}/checks.meta.json').writeAsStringSync(
      jsonEncode({
        'catalogSha256': catalogSha(),
        'buildHash': buildHash(),
        'catalogCommit': 'test',
        'exitCodes': <String, int>{},
      }),
    );
  }

  /// One harness record: per-frame columns the aggregator reads.
  String record(
    String id, {
    required double cpu,
    required double gpu,
    int failed = 0,
  }) => jsonEncode({
    'id': id,
    'label': 'iphone',
    'fps': 30,
    'warmup': 1,
    'cols': {
      'cpu_thread_ms': [9.0, cpu, cpu, cpu],
      'gpu_ms': [9.0, gpu, gpu, gpu],
      'wall_ms': [9.0, cpu + gpu, cpu + gpu, cpu + gpu],
      'native_cpu_ms': [0.0, 0.001, 0.001, 0.001],
      'dry_passes': [1, 1, 2, 1],
      'dry_bytes': [1000000, 1000000, 2000000, 1000000],
      'failed': [0, 0, failed, 0],
    },
  });

  void writeHarness({
    double alphaCpu = 0.25,
    double alphaGpu = 0.1,
    int alphaFailed = 0,
  }) {
    final dir = Directory('${evidence.path}/harness/rd1/iphone')
      ..createSync(recursive: true);
    File('${dir.path}/batch_000.jsonl').writeAsStringSync(
      [
        record('plasma_scene', cpu: 0.233, gpu: 0.0549),
        record('synthwave_scene', cpu: 0.874, gpu: 0.321),
        record('alpha', cpu: alphaCpu, gpu: alphaGpu, failed: alphaFailed),
      ].join('\n'),
    );
    File(
      '${dir.path}/batch_000.meta.json',
    ).writeAsStringSync(jsonEncode({'clean': true}));
  }

  /// SYNTHETIC energy contract shaped like scene_energy_budget_v1.json: only
  /// the places the tool reads, with made-up but plausible numbers.
  File writeContract({double backgroundGpu = 839.4}) {
    Map<String, Object> q(Object value) => {
      'value': value,
      'confidence': 'synthetic',
    };
    final file =
        File('${repo.path}/contract/scene_energy_budget_v1.json')
          ..createSync(recursive: true)
          ..writeAsStringSync(
            jsonEncode({
              'schemaVersion': 1,
              'revision': 'scene-energy-budget-v1',
              'summary': 'SYNTHETIC test fixture, not the app contract',
              'reference': {
                'device': {
                  'model': 'iPhone 14 Pro',
                  'identifier': 'iPhone15,2',
                  'operatingSystem': 'iOS 27',
                },
                'surface': {'width': q(664), 'height': q(1440)},
                'measurementConditions': {'certificationSoakMinutes': q(60)},
              },
              'elements': {
                'catalogProgram': {
                  'requirements': {
                    'measurementWarmupSeconds': q(15),
                    'measurementCpuWindowSecondsMinimum': q(15),
                    'measurementGpuWindowSeconds': q(10),
                    'measurementSurfaceWidth': q(664),
                    'measurementSurfaceHeight': q(1440),
                    'measurementMsaaSamples': q(4),
                    'measuredToMacEstimateRatioMinimum': q(0.75),
                    'measuredToMacEstimateRatioMaximum': q(1.85),
                    'macToReferenceFactor': q(28.47),
                  },
                },
                'creatorProgram': {
                  'requirements': {
                    'feasibilityRule': q(
                      'gpuMsPerFrame + cpuMsPerFrame <= 1000 / framesPerSecond',
                    ),
                    'defaultFramesPerSecond': q(30),
                    'maximumFramesPerSecond': q(60),
                    'maximumIntermediatePassesAtReference': q(35),
                    'maximumIntermediatePassesAtIpad': q(28),
                    'runtimeMaximumPasses': q(192),
                    'runtimeMaximumRetainedBytes': q(134217728),
                  },
                },
              },
              'slotCeilings': {
                'comparison': {
                  'gpuMarginPercent': q(3),
                  'efficiencyCoreMarginPercent': q(25),
                  'performanceCorePercentOfCoreBound': q(3),
                },
                'slots': {
                  'backgroundProgram': {
                    'measured': {
                      'appGpuMsPerSecond': q(backgroundGpu),
                      'efficiencyCorePercentOfCore': q(40.97),
                    },
                  },
                  'overlayProgram': {
                    'measured': {
                      'appGpuMsPerSecond': q(184.54),
                      'efficiencyCorePercentOfCore': q(46.23),
                    },
                  },
                },
              },
            }),
          );
    return file;
  }

  int run(List<String> args) {
    out.clear();
    err.clear();
    return runReadiness(
      [...args, '--catalog', catalog.path],
      out: out,
      err: err,
    );
  }

  Map<String, Object?> registry() =>
      jsonDecode(
            File('${catalog.path}/readiness/registry.json').readAsStringSync(),
          )
          as Map<String, Object?>;
  Map<String, Object?> entry(String id) =>
      (registry()['visuals'] as Map)[id] as Map<String, Object?>;
  Map<String, Object?> check(String id, String name) =>
      (entry(id)['checks'] as Map)[name] as Map<String, Object?>;

  /// SYNTHETIC energy probe row (energy_probe.py creator mode) with the
  /// artifacts the producer leaves for it: the console log (`[ENERGY_PROBE]`
  /// lines) and the `-probe.jsonl` snapshot of the same lines with host
  /// time, both consistent with the row unless [record] or [logText] say
  /// otherwise. [row] overrides row fields, [creator] the identity.
  var probeIndex = 0;
  File writeRows(
    CreatorVisualDefinition visual, {
    Map<String, Object?> row = const {},
    Map<String, Object?> creator = const {},
    Map<String, Object?> record = const {},
    Map<String, Object?>? device,
    Map<String, Object?>? viewport,
    (int, int)? surfacePx = (664, 1440),
    bool surfaceAttached = true,
    String profile = 'default',
    String? variation,
    String? logText,
    bool append = false,
  }) {
    final probe = Directory('${repo.path}/probe')..createSync(recursive: true);
    final index = ++probeIndex;
    final log = File('${probe.path}/$index-${visual.id}-console.log');
    final snapshot = File('${probe.path}/$index-${visual.id}-probe.jsonl');
    final fps = visual.framesPerSecond;
    final identity = <String, Object?>{
      'visualId': visual.id,
      'programId': visual.programId,
      'kind': visual.isNative ? 'native' : 'shader',
      'programHash': ReadinessTool.programHash(visual),
      'revision': visualRevision(visual),
      'buildHash': buildHash(),
      'profile': {
        'name': profile,
        'variation': variation,
        'controls': visual.controls.toMap(),
        'modifiers': visual.modifierDefaults,
      },
      'framesPerSecond': fps,
      'reactive': visual.reactivity != CreatorReactivity.none,
      'signal':
          visual.reactivity == CreatorReactivity.none ? null : 'synthetic_loud',
      'role': visual.role.name,
      ...creator,
    };
    final deviceMap =
        device ??
        {
          'model': 'iPhone15,2',
          'systemName': 'iOS',
          'systemVersion': '27.0.1',
          'isPhysical': true,
          'displayHz': 120,
        };
    final viewportMap =
        viewport ??
        {
          'logicalWidth': 393.0,
          'logicalHeight': 852.0,
          'devicePixelRatio': 3.0,
        };
    final rowMap = <String, Object?>{
      'schemaVersion': 1,
      'id': profile == 'default' ? visual.id : '${visual.id}@$profile',
      'role': visual.role.name,
      'scheduleIndex': index,
      'status': 'measured',
      'targetKind': 'creator',
      'utc': '2026-10-07T2${index % 10}:00:00+00:00',
      'attempts': 1,
      'startThermal': 'nominal',
      'warmupS': 15.0,
      'windowS': 20,
      'windowSource': 'toc',
      'traceSpanS': 20.1,
      'gpuSpanS': 10.2,
      'appPid': 4242,
      'runnerPids': [4242],
      'thermalStates': ['nominal'],
      'energyLevel': 'best',
      'charging': true,
      'lowPower': false,
      'probeSamples': 16,
      'surfaceSamples': 16,
      'pendingMediaSamples': 0,
      'achievedFps': fps.toDouble(),
      'gpuAppMsPerSecond': 120.0,
      'gpuAppMsPerPublishedFrame': 120.0 / fps,
      'runnerEPercent': 30.0,
      'runnerSPercent': 0.4,
      'renderThreadPercent': 10.0,
      'memMb': 200.0,
      'warnings': ['charging'],
      'consoleLog': log.path,
      'creator': identity,
      'device': deviceMap,
      'viewport': viewportMap,
      ...row,
    };
    // The probe lines: one attached record, then the measured window after
    // the warmup, each reproducing the row's summary.
    final thermal = rowMap['thermalStates'] as List;
    final samples = (rowMap['probeSamples'] as num).toInt();
    final warmup = (rowMap['warmupS'] as num).toDouble();
    Map<String, Object?> line(int i, double hostTime) => {
      'hostTime': hostTime,
      'epochMs': 1700000000000 + (hostTime * 1000).round(),
      'visual': visual.id,
      'intervalS': 2.0,
      'thermal': thermal.isEmpty ? 'nominal' : thermal[i % thermal.length],
      'lowPower': rowMap['lowPower'],
      'charging': rowMap['charging'],
      'memMb': rowMap['memMb'],
      'surface': surfaceAttached,
      'preparing': false,
      'playing': true,
      'publishedFps': rowMap['achievedFps'],
      'energyLevel': rowMap['energyLevel'],
      'pendingMedia': false,
      if (surfaceAttached && surfacePx != null)
        'surfacePx': {'width': surfacePx.$1, 'height': surfacePx.$2},
      'creator': identity,
      'device': deviceMap,
      'viewport': viewportMap,
      ...record,
    };
    final records = [
      line(0, 1000.0),
      for (var i = 0; i < samples; i++) line(i, 1000.0 + warmup + 1 + 2 * i),
    ];
    snapshot.writeAsStringSync(
      [for (final r in records) jsonEncode(r)].join('\n') + '\n',
    );
    log.writeAsStringSync(
      logText ??
          [
                for (final r in records)
                  'Runner[1:2] [ENERGY_PROBE] ${jsonEncode(Map.of(r)..remove('hostTime'))}',
              ].join('\n') +
              '\n',
    );
    final trace = File('${probe.path}/$index-${visual.id}-trace-samples.json');
    final traceStart = 1000.0 + warmup + 1;
    trace.writeAsStringSync(
      jsonEncode(syntheticCreatorTrace(rowMap, traceStart)),
    );
    rowMap['traceEvidence'] = {
      'file': trace.path,
      'sha256': sha256.convert(trace.readAsBytesSync()).toString(),
    };
    rowMap['probeWindowStartEpochS'] = traceStart;
    rowMap['probeWindowEndEpochS'] =
        traceStart +
        (rowMap['traceSpanS'] as num) +
        (rowMap['gpuSpanS'] as num);
    final rows = File('${probe.path}/energy_probe.jsonl');
    rows.writeAsStringSync(
      '${jsonEncode(rowMap)}\n',
      mode: append ? FileMode.append : FileMode.write,
    );
    return rows;
  }

  int importCards(File rows) => run(['cards', 'import', '--rows', rows.path]);

  setUp(() {
    repo = Directory.systemTemp.createTempSync('readiness-');
    catalog = Directory('${repo.path}/packages/visual_catalog')
      ..createSync(recursive: true);
    evidence = Directory('${repo.path}/evidence')..createSync();
    out = StringBuffer();
    err = StringBuffer();
    probeIndex = 0;
    writeEngine();
    writeCatalog([alpha, beta, plasma, synthwave]);
    expect(
      run(['contract', 'import', writeContract().path]),
      0,
      reason: err.toString(),
    );
    writeChecks();
    writeHarness();
  });
  tearDown(() => repo.deleteSync(recursive: true));

  test(
    'every check is parsed per visual and nothing is verified without a device card',
    () {
      expect(
        run(['prepare', '--evidence', evidence.path]),
        0,
        reason: err.toString(),
      );
      final alphaEntry = entry('alpha');
      expect(alphaEntry['state'], 'pendingEvidence');
      expect(alphaEntry['revision'], visualRevision(alpha));
      expect(alphaEntry['programHash'], 'hash-alpha-1');
      expect(check('alpha', 'nativeReplay')['status'], 'pass');
      expect(check('alpha', 'modifierSweep')['status'], 'pass');
      expect(check('alpha', 'passGate')['status'], 'warn');
      expect((check('alpha', 'passGate')['iPhone'] as Map)['passes'], 3);
      expect((check('alpha', 'passGate')['harnessSchedule'] as Map)['fps'], 60);
      expect(check('alpha', 'metalScene')['status'], 'pass');
      expect(check('alpha', 'metalBehavior')['status'], 'pass');
      expect(check('alpha', 'hostCost')['status'], 'info');
      expect(check('alpha', 'hostCost')['verdict'], isNotNull);
      expect(check('alpha', 'deviceCard')['status'], 'pending');
      expect(alphaEntry['scope'], contains('valores iniciales'));
      for (final name in ['nativeReplay', 'passGate']) {
        expect(check('alpha', name)['proves'], isNotEmpty);
        expect(check('alpha', name)['doesNotProve'], isNotEmpty);
      }
      // The old shader goes through its own checker; the Mac harness never
      // measured shaders and the contract never asked for it.
      expect(check('beta', 'nativeReplay')['status'], 'notApplicable');
      expect(check('beta', 'metalScene')['status'], 'pass');
      expect(check('beta', 'metalBehavior')['status'], 'pass');
      expect(check('beta', 'hostCost')['status'], 'notApplicable');
      expect(entry('beta')['state'], 'pendingEvidence');
      // The registry names the build it describes and the contract copy.
      final engine = registry()['engine'] as Map;
      expect(engine['buildHash'], buildHash());
      expect(
        (registry()['energyContract'] as Map)['revision'],
        'scene-energy-budget-v1',
      );
      expect(
        (registry()['energyContract'] as Map)['semanticHash'],
        isA<String>(),
      );
      // The studio export has no hashes beyond the vote revision, plus the
      // engine stamp it compares with its bundled manifest.
      final export =
          jsonDecode(
                File(
                  '${catalog.path}/readiness/studio_readiness.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      final exported = (export['visuals'] as Map)['alpha'] as Map;
      expect(exported.keys.toSet(), {'revision', 'state', 'detail', 'scope'});
      expect((export['engine'] as Map)['buildHash'], buildHash());
      final readiness = CreatorReadiness.parse(jsonEncode(export));
      expect(
        readiness.entryFor('alpha', visualRevision(alpha)).state,
        CreatorReadinessState.pendingEvidence,
      );
      expect(
        readiness.entryFor('alpha', 'other').state,
        CreatorReadinessState.unknown,
      );
      expect(readiness.engineMismatch(buildHash()), CreatorEngineMismatch.none);
      expect(
        readiness.engineMismatch('other-build'),
        CreatorEngineMismatch.changed,
      );
      expect(
        readiness.engineMismatch(null),
        CreatorEngineMismatch.manifestMissing,
      );
      expect(
        readiness
            .entryFor(
              'alpha',
              visualRevision(alpha),
              engine: CreatorEngineMismatch.changed,
            )
            .state,
        CreatorReadinessState.unknown,
      );
      // An export without a stamp is unknown, never "matched".
      final unstamped = CreatorReadiness.parse(
        jsonEncode({...export, 'engine': <String, Object?>{}}),
      );
      expect(
        unstamped.engineMismatch(buildHash()),
        CreatorEngineMismatch.exportWithoutStamp,
      );
      expect(
        File('${catalog.path}/readiness/revision_links.json').existsSync(),
        isTrue,
      );
      expect(out.toString(), contains('pendingEvidence 4'));
    },
  );

  test('a missing or stopped check is "not run", never a pass', () {
    writeChecks(shaders: false);
    File('${evidence.path}/checks/check_creator_scenes.log').writeAsStringSync(
      'PASS authored creator_alpha: native Metal scene, alpha and state replay\n'
      'PASS behavior creator_alpha: optional, identical-history musical/neutral probes\n'
      'Fatal error: SceneCreatorFailure(creator_plasma_scene: Native catalog rejected)\n',
    );
    expect(
      run(['prepare', '--evidence', evidence.path]),
      0,
      reason: err.toString(),
    );
    expect(check('beta', 'metalScene')['status'], 'notRun');
    expect(entry('beta')['detail'], contains('Faltan pruebas Mac'));
    expect(check('plasma_scene', 'metalScene')['status'], 'fail');
    expect(entry('plasma_scene')['state'], 'needsRepair');
    expect(check('synthwave_scene', 'metalScene')['status'], 'notRun');
    expect(
      check('synthwave_scene', 'metalScene')['detail'],
      contains('se detuvo'),
    );
  });

  test('a failed Mac check or a dead modifier needs repair', () {
    writeChecks(
      nativeExtra:
          'FAIL alpha: 40 pasadas por cuadro en el iPhone (máx 35) y 145,9 MiB (máx 128)\n'
          'FAIL plasma_scene: el modificador nada no cambia nada, ni en sus extremos ni con música.\n',
    );
    expect(
      run(['prepare', '--evidence', evidence.path]),
      0,
      reason: err.toString(),
    );
    expect(entry('alpha')['state'], 'needsRepair');
    expect(check('alpha', 'passGate')['status'], 'fail');
    expect(entry('alpha')['detail'], contains('pasadas'));
    expect(entry('plasma_scene')['state'], 'needsRepair');
    expect(check('plasma_scene', 'modifierSweep')['status'], 'fail');
  });

  test(
    'a Mac estimate never forces needsRepair; only a proven failure does',
    () {
      // An "infeasible" Mac estimate is extrapolated from two anchors: it sets
      // a measurement priority, it never proves a failure.
      writeHarness(alphaCpu: 7.0, alphaGpu: 0.7);
      expect(
        run(['prepare', '--evidence', evidence.path]),
        0,
        reason: err.toString(),
      );
      expect(check('alpha', 'hostCost')['verdict'], 'infeasible');
      expect(entry('alpha')['state'], 'pendingEvidence');
      expect(entry('alpha')['measurementPriority'], contains('medir-primero'));
      expect(entry('alpha')['detail'], contains('prioridad alta'));
      // A plain over-ceiling estimate also only asks for the device.
      writeHarness(alphaCpu: 1.2, alphaGpu: 0.3);
      expect(
        run(['prepare', '--evidence', evidence.path]),
        0,
        reason: err.toString(),
      );
      expect(check('alpha', 'hostCost')['verdict'], 'verifyOnDevice');
      expect(entry('alpha')['state'], 'pendingEvidence');
      expect(entry('alpha')['detail'], contains('medición física'));
      // A harness frame over the production guard IS a proven failure.
      writeHarness(alphaFailed: 3);
      expect(
        run(['prepare', '--evidence', evidence.path]),
        0,
        reason: err.toString(),
      );
      expect(check('alpha', 'hostCost')['status'], 'fail');
      expect(entry('alpha')['state'], 'needsRepair');
    },
  );

  test(
    'checks of another build are refused: a Swift-only change must rerun them',
    () {
      expect(
        run(['prepare', '--evidence', evidence.path]),
        0,
        reason: err.toString(),
      );
      writeEngine(runtime: 'swift v2');
      expect(run(['prepare', '--evidence', evidence.path]), 1);
      expect(err.toString(), contains('otro motor'));
      writeChecks();
      expect(
        run(['prepare', '--evidence', evidence.path]),
        0,
        reason: err.toString(),
      );
    },
  );

  test(
    'a device card verifies only its own row and log for this exact program, build and profile',
    () {
      expect(
        run(['prepare', '--evidence', evidence.path]),
        0,
        reason: err.toString(),
      );
      final rows = writeRows(alpha);
      writeRows(beta, append: true);
      expect(importCards(rows), 0, reason: err.toString());
      final cards =
          jsonDecode(
                File(
                  '${catalog.path}/readiness/device_cards.json',
                ).readAsStringSync(),
              )
              as Map;
      expect((cards['cards'] as Map).keys.toSet(), {'alpha', 'beta'});
      expect(
        run(['prepare', '--evidence', evidence.path]),
        0,
        reason: err.toString(),
      );
      expect(entry('alpha')['state'], 'verified');
      expect(entry('alpha')['scope'], startsWith('valores iniciales'));
      expect(
        entry('alpha')['scope'],
        isNot(contains('todos los ajustes al máximo')),
      );
      expect(check('alpha', 'deviceCard')['status'], 'within');
      // An old shader with a valid card is verified too (no Mac estimate needed).
      expect(entry('beta')['state'], 'verified');
      expect(out.toString(), contains('verified 2'));
      // The card survives a refresh while program, build and contract hold...
      expect(
        run(['prepare', '--evidence', evidence.path]),
        0,
        reason: err.toString(),
      );
      expect(entry('alpha')['state'], 'verified');
      // ...and stops certifying when the shared runtime changes: the vote
      // revision survives, the technical certification does not.
      final revisionBefore = entry('alpha')['revision'];
      final identityBefore = entry('alpha')['technicalIdentity'];
      writeEngine(runtime: 'swift v2');
      writeChecks();
      expect(
        run(['prepare', '--evidence', evidence.path]),
        0,
        reason: err.toString(),
      );
      expect(entry('alpha')['revision'], revisionBefore);
      expect(entry('alpha')['technicalIdentity'], isNot(identityBefore));
      expect(entry('alpha')['state'], 'pendingEvidence');
      expect(check('alpha', 'deviceCard')['detail'], contains('otro motor'));
      // A changed check tool changes the build too.
      writeEngine(runtime: 'swift v2', checks: 'another test');
      writeChecks();
      expect(
        run(['prepare', '--evidence', evidence.path]),
        0,
        reason: err.toString(),
      );
      expect(entry('alpha')['state'], 'pendingEvidence');
    },
  );

  test('a partial card covers only its profile; the initial values decide', () {
    expect(
      run(['prepare', '--evidence', evidence.path]),
      0,
      reason: err.toString(),
    );
    // Only the maximum measured: nothing verified for the app's own profile.
    var rows = writeRows(alpha, profile: 'max');
    expect(importCards(rows), 0, reason: err.toString());
    expect(
      run(['prepare', '--evidence', evidence.path]),
      0,
      reason: err.toString(),
    );
    expect(entry('alpha')['state'], 'pendingEvidence');
    expect(
      check('alpha', 'deviceCard')['detail'],
      contains('valores iniciales'),
    );
    // Initial values within, maximum within: both covered, listed.
    writeRows(alpha, append: true);
    expect(importCards(rows), 0, reason: err.toString());
    expect(
      run(['prepare', '--evidence', evidence.path]),
      0,
      reason: err.toString(),
    );
    expect(entry('alpha')['state'], 'verified');
    expect(entry('alpha')['scope'], contains('valores iniciales'));
    expect(entry('alpha')['scope'], contains('todos los ajustes al máximo'));
    // A variation over its ceiling: verified for the rest, not for it.
    writeRows(
      alpha,
      profile: 'variation',
      variation: 'Densa',
      row: {'runnerEPercent': 90.0},
      append: true,
    );
    expect(importCards(rows), 0, reason: err.toString());
    expect(
      run(['prepare', '--evidence', evidence.path]),
      0,
      reason: err.toString(),
    );
    expect(entry('alpha')['state'], 'verified');
    expect(entry('alpha')['scope'], isNot(contains('Densa')));
    final profiles = check('alpha', 'deviceCard')['profiles'] as List;
    expect(
      profiles.where((p) => (p as Map)['status'] == 'exceeds'),
      hasLength(1),
    );
    // Initial values over the ceiling: exceeds, never verified.
    rows = writeRows(alpha, row: {'runnerEPercent': 90.0});
    expect(importCards(rows), 0, reason: err.toString());
    expect(
      run(['prepare', '--evidence', evidence.path]),
      0,
      reason: err.toString(),
    );
    expect(entry('alpha')['state'], 'pendingEvidence');
    expect(check('alpha', 'deviceCard')['status'], 'exceeds');
  });

  test('an invalid, incomplete or stale card never verifies', () {
    expect(
      run(['prepare', '--evidence', evidence.path]),
      0,
      reason: err.toString(),
    );
    void expectPending(File rows, String detail, {bool import = true}) {
      if (import) expect(importCards(rows), 0, reason: err.toString());
      expect(
        run(['prepare', '--evidence', evidence.path]),
        0,
        reason: err.toString(),
      );
      expect(entry('alpha')['state'], 'pendingEvidence', reason: detail);
      expect(check('alpha', 'deviceCard')['status'], 'pending', reason: detail);
      expect(check('alpha', 'deviceCard')['detail'], contains(detail));
    }

    // The console log changed (or was replaced) after the import.
    var rows = writeRows(alpha);
    expect(importCards(rows), 0, reason: err.toString());
    File('${repo.path}/probe/1-alpha-console.log').writeAsStringSync('edited');
    expectPending(rows, 'log de consola cambió', import: false);
    // The log is gone.
    File('${repo.path}/probe/1-alpha-console.log').deleteSync();
    expectPending(rows, 'falta el log', import: false);
    // The rows file changed after the import.
    rows = writeRows(alpha);
    expect(importCards(rows), 0, reason: err.toString());
    rows.writeAsStringSync('\n', mode: FileMode.append);
    expectPending(rows, 'cambió desde la importación', import: false);
    // Simulator, or another device / OS than the reference.
    expectPending(
      writeRows(
        alpha,
        device: {
          'model': 'iPhone15,2',
          'systemVersion': '27.0',
          'isPhysical': false,
        },
      ),
      'físico',
    );
    expectPending(
      writeRows(
        alpha,
        device: {
          'model': 'iPad13,4',
          'systemVersion': '27.0',
          'isPhysical': true,
        },
      ),
      'referencia iPhone15,2',
    );
    expectPending(
      writeRows(
        alpha,
        device: {
          'model': 'iPhone15,2',
          'systemVersion': '26.1',
          'isPhysical': true,
        },
      ),
      'sistema 26.1',
    );
    // No frames, or a cadence below the visual's.
    expectPending(writeRows(alpha, row: {'achievedFps': 0.0}), 'alcanza 0');
    expectPending(
      writeRows(
        alpha,
        row: {'achievedFps': 31.0, 'gpuAppMsPerPublishedFrame': 120.0 / 31.0},
      ),
      'alcanza 31',
    );
    // Measured at 30 fps for a 60 fps visual: never carried to 60.
    expectPending(
      writeRows(
        alpha,
        creator: {'framesPerSecond': 30},
        row: {'achievedFps': 30.0},
      ),
      'corrió a 30 fps',
    );
    // Another measured surface than the reference; a viewport alone never
    // stands in for the surface the device drew.
    expectPending(
      writeRows(alpha, surfacePx: (900, 1294)),
      'superficie 900×1294',
    );
    expectPending(
      writeRows(
        alpha,
        surfacePx: null,
        viewport: {
          'logicalWidth': 393.0,
          'logicalHeight': 852.0,
          'devicePixelRatio': 3.0,
        },
      ),
      'sin superficie medida',
    );
    // Protocol too short, no warmup, thermal not nominal, governor engaged.
    expectPending(writeRows(alpha, row: {'traceSpanS': 8.0}), 'ventana de CPU');
    expectPending(writeRows(alpha, row: {'gpuSpanS': 2.0}), 'ventana de GPU');
    expectPending(writeRows(alpha, row: {'warmupS': 0.0}), 'warmup');
    expectPending(
      writeRows(
        alpha,
        row: {
          'thermalStates': ['nominal', 'fair'],
        },
      ),
      'térmico',
    );
    expectPending(writeRows(alpha, row: {'startThermal': 'fair'}), 'térmico');
    expectPending(
      writeRows(alpha, row: {'energyLevel': 'sustained'}),
      'energía sustained',
    );
    expectPending(
      writeRows(
        alpha,
        row: {
          'warnings': ['no gpu samples'],
        },
      ),
      'avisa',
    );
    // A row that was not measured is never imported as a card.
    expectPending(writeRows(alpha, row: {'status': 'skipped'}), 'sin ficha');
    // Numbers that are not measurements.
    expectPending(
      writeRows(alpha, row: {'gpuAppMsPerSecond': -1.0}),
      'no finita o negativa',
    );
    expectPending(
      writeRows(alpha, row: {'runnerEPercent': 'NaN'}),
      'no finita o negativa',
    );
    expectPending(
      writeRows(alpha, row: {'gpuAppMsPerPublishedFrame': null}),
      'no finita o negativa',
    );
    // The probe measured another program, revision or build; or none.
    expectPending(
      writeRows(alpha, creator: {'programHash': 'hash-alpha-2'}),
      'otro programa',
    );
    expectPending(
      writeRows(alpha, creator: {'revision': 'ffff'}),
      'otra revisión',
    );
    expectPending(
      writeRows(alpha, creator: {'buildHash': 'other-build'}),
      'otro motor',
    );
    expectPending(
      writeRows(alpha, creator: {'buildHash': null}),
      'manifiesto de build',
    );
    expectPending(
      writeRows(alpha, creator: {'signal': null}),
      'señal sintética',
    );
    // Feasibility: GPU + CPU per frame over the frame budget.
    expectPending(
      writeRows(alpha, row: {'gpuAppMsPerPublishedFrame': 20.0}),
      'incoherente',
    );
    // A card stays bound to the contract it was judged with: the same
    // revision with other content is another contract.
    rows = writeRows(alpha);
    expect(importCards(rows), 0, reason: err.toString());
    expect(
      run(['prepare', '--evidence', evidence.path]),
      0,
      reason: err.toString(),
    );
    expect(entry('alpha')['state'], 'verified');
    final live = writeContract(backgroundGpu: 500.0);
    expect(
      run([
        'prepare',
        '--evidence',
        evidence.path,
        '--energy-contract',
        live.path,
      ]),
      1,
      reason: err.toString(),
    );
    expect(err.toString(), contains('otro motor'));
    expect(out.toString(), contains('difiere de la copia registrada'));
    writeChecks();
    expect(
      run([
        'prepare',
        '--evidence',
        evidence.path,
        '--energy-contract',
        live.path,
      ]),
      0,
      reason: err.toString(),
    );
    expect(entry('alpha')['state'], 'pendingEvidence');
    expect(check('alpha', 'deviceCard')['detail'], contains('otro contrato'));
    expect((registry()['energyContract'] as Map)['matchesLive'], isTrue);
    // Re-importing old measurements cannot claim they ran the new build.
    expect(importCards(rows), 0, reason: err.toString());
    expect(
      run(['prepare', '--evidence', evidence.path]),
      0,
      reason: err.toString(),
    );
    expect(entry('alpha')['state'], 'pendingEvidence');
    rows = writeRows(alpha);
    expect(importCards(rows), 0, reason: err.toString());
    expect(
      run(['prepare', '--evidence', evidence.path]),
      0,
      reason: err.toString(),
    );
    expect(entry('alpha')['state'], 'verified');
    // No contract copy at all: nothing certifies, and it says why.
    File('${catalog.path}/readiness/energy_contract.json').deleteSync();
    expect(
      run(['prepare', '--evidence', evidence.path]),
      1,
      reason: err.toString(),
    );
    writeChecks();
    expect(
      run(['prepare', '--evidence', evidence.path]),
      0,
      reason: err.toString(),
    );
    expect(out.toString(), contains('sin copia del contrato'));
    expect(entry('alpha')['state'], 'pendingEvidence');
    expect(check('alpha', 'deviceCard')['detail'], contains('contrato'));
  });

  test(
    'an arbitrary console, an invented row or a tampered probe snapshot never verifies',
    () {
      expect(
        run(['prepare', '--evidence', evidence.path]),
        0,
        reason: err.toString(),
      );
      void expectPending(File rows, String detail, {bool import = true}) {
        if (import) expect(importCards(rows), 0, reason: err.toString());
        expect(
          run(['prepare', '--evidence', evidence.path]),
          0,
          reason: err.toString(),
        );
        expect(entry('alpha')['state'], 'pendingEvidence', reason: detail);
        expect(
          check('alpha', 'deviceCard')['status'],
          'pending',
          reason: detail,
        );
        expect(check('alpha', 'deviceCard')['detail'], contains(detail));
      }

      // A console that only names the visual, whatever its hash.
      expectPending(
        writeRows(
          alpha,
          logText: 'Runner[1:2] [ENERGY_PROBE] {"visual":"alpha"}\n',
        ),
        'log de consola',
      );
      // Row numbers the probe lines do not reproduce.
      expectPending(
        writeRows(alpha, record: {'publishedFps': 59.0}),
        'no reproducen la fila',
      );
      expectPending(
        writeRows(alpha, record: {'memMb': 199.0}),
        'no reproducen la fila',
      );
      // GPU/s edited in the row: incoherent with GPU per frame and cadence.
      expectPending(
        writeRows(alpha, row: {'gpuAppMsPerSecond': 90.0}),
        'incoherente',
      );
      // The probe snapshot: missing, altered, or not the log's lines.
      var rows = writeRows(alpha);
      expect(importCards(rows), 0, reason: err.toString());
      final snapshot = File('${repo.path}/probe/$probeIndex-alpha-probe.jsonl');
      final original = snapshot.readAsStringSync();
      snapshot.writeAsStringSync(
        original.replaceFirst('"memMb":200.0', '"memMb":201.0'),
      );
      expectPending(rows, 'snapshot de la sonda cambió', import: false);
      snapshot.deleteSync();
      expectPending(rows, 'falta el snapshot', import: false);
      snapshot.writeAsStringSync(original);
      final log = File('${repo.path}/probe/$probeIndex-alpha-console.log');
      log.writeAsStringSync(
        log.readAsStringSync().replaceFirst('"memMb":200.0', '"memMb":201.0'),
      );
      expectPending(rows, 'log de consola cambió', import: false);
      // The CPU trace link: the window must come from the trace TOC and the
      // trace must name the app pid.
      expectPending(writeRows(alpha, row: {'windowSource': 'command'}), 'TOC');
      expectPending(
        writeRows(alpha, record: {'playing': false}),
        'reproducción pausada',
      );
      expectPending(
        writeRows(alpha, record: {'playing': null}),
        'reproducción pausada o desconocida',
      );
      expectPending(writeRows(alpha, row: {'appPid': null}), 'PID');
      expectPending(
        writeRows(
          alpha,
          row: {
            'runnerPids': [1, 2],
          },
        ),
        'pid',
      );
      expectPending(
        writeRows(
          alpha,
          row: {
            'warnings': ['no cpu trace'],
          },
        ),
        'no cpu trace',
      );
      // A legacy shader without a native surface needs the trace route for
      // GPU and a measured cadence; without data it stays pending.
      rows = writeRows(
        beta,
        surfaceAttached: false,
        row: {'surfaceSamples': 0},
      );
      expect(importCards(rows), 0, reason: err.toString());
      expect(
        run(['prepare', '--evidence', evidence.path]),
        0,
        reason: err.toString(),
      );
      expect(entry('beta')['state'], 'pendingEvidence');
      expect(check('beta', 'deviceCard')['detail'], contains('ruta legacy'));
      // The GPU window follows the contract value, not a fraction of it.
      expectPending(
        writeRows(alpha, row: {'gpuSpanS': 9.9}),
        'ventana de GPU 9.9',
      );
    },
  );

  test(
    'another device measures with an explicit profile and its own scope, never as the reference',
    () {
      expect(
        run(['prepare', '--evidence', evidence.path]),
        0,
        reason: err.toString(),
      );
      final ipad = {
        'model': 'iPad13,4',
        'systemName': 'iPadOS',
        'systemVersion': '27.0',
        'isPhysical': true,
        'displayHz': 120,
      };
      // No profile registered: not the reference, nothing else.
      var rows = writeRows(alpha, device: ipad, surfacePx: (900, 1296));
      expect(importCards(rows), 0, reason: err.toString());
      expect(run(['prepare', '--evidence', evidence.path]), 0);
      expect(check('alpha', 'deviceCard')['status'], 'pending');
      expect(
        check('alpha', 'deviceCard')['detail'],
        contains('sin perfil registrado'),
      );
      // A profile for that identifier with its measured surface: backed
      // evidence with the iPad scope; no ceiling, no certification.
      File('${catalog.path}/readiness/device_profiles.json').writeAsStringSync(
        jsonEncode({
          'schemaVersion': 1,
          'devices': {
            'iPad13,4': {
              'operatingSystem': 'iPadOS 27',
              'surfaceWidth': 900,
              'surfaceHeight': 1296,
              'scope': 'iPad',
            },
          },
        }),
      );
      expect(run(['prepare', '--evidence', evidence.path]), 0);
      expect(entry('alpha')['state'], 'pendingEvidence');
      final card = check('alpha', 'deviceCard');
      expect(card['status'], 'pending');
      expect(card['detail'], contains('alcance iPad'));
      expect(card['detail'], contains('no equivale a la referencia'));
      final profiles = card['profiles'] as List;
      expect(profiles.single, containsPair('status', 'pending'));
      // Its measured surface still has to be the profile's.
      rows = writeRows(alpha, device: ipad, surfacePx: (664, 1440));
      expect(importCards(rows), 0, reason: err.toString());
      expect(run(['prepare', '--evidence', evidence.path]), 0);
      expect(
        check('alpha', 'deviceCard')['detail'],
        contains('superficie 664×1440 ≠ 900×1296 de iPad13,4'),
      );
      // The iPad profile never covers another device.
      rows = writeRows(
        alpha,
        device: {...ipad, 'model': 'iPad14,1'},
        surfacePx: (900, 1296),
      );
      expect(importCards(rows), 0, reason: err.toString());
      expect(run(['prepare', '--evidence', evidence.path]), 0);
      expect(
        check('alpha', 'deviceCard')['detail'],
        contains('iPad14,1 ≠ referencia iPhone15,2 y sin perfil registrado'),
      );
      // The reference keeps certifying with the profile file present.
      rows = writeRows(alpha);
      expect(importCards(rows), 0, reason: err.toString());
      expect(run(['prepare', '--evidence', evidence.path]), 0);
      expect(entry('alpha')['state'], 'verified');
    },
  );

  test(
    'a device envelope requires one sustained raw anchor and keeps its scope',
    () {
      expect(run(['prepare', '--evidence', evidence.path]), 0);
      final ipad = {
        'model': 'iPad13,4',
        'systemName': 'iPadOS',
        'systemVersion': '27.0',
        'isPhysical': true,
        'displayHz': 120,
      };
      final anchorRows = writeRows(
        alpha,
        device: ipad,
        surfacePx: (900, 1296),
        record: {'brightness': 0.5},
      ).renameSync('${repo.path}/probe/anchor-rows.jsonl');
      expect(importCards(anchorRows), 0);
      Map<String, Object?> currentCard() =>
          (((jsonDecode(
                                File(
                                  '${catalog.path}/readiness/device_cards.json',
                                ).readAsStringSync(),
                              )
                              as Map)['cards']
                          as Map)['alpha']
                      as List)
                  .single
              as Map<String, Object?>;
      final anchorCard = currentCard();
      final base =
          jsonDecode(
                File(
                  anchorCard['probe'] is Map
                      ? (anchorCard['probe'] as Map)['file'] as String
                      : '',
                ).readAsLinesSync().first,
              )
              as Map<String, Object?>;
      final soakLog = File('${repo.path}/probe/soak-console.log');
      final soakProbe = File('${repo.path}/probe/soak-probe.jsonl');
      Map<String, Object?> ref(File f) => {
        'file': f.path,
        'sha256': sha256.convert(f.readAsBytesSync()).toString(),
      };
      void writeSoak({int count = 1818, bool hot = false, bool gap = false}) {
        final records = [
          for (var i = 0; i < count; i++)
            {
              ...base,
              'hostTime': 1000.0 + 2 * i + (gap && i > 900 ? 10 : 0),
              'epochMs':
                  (base['epochMs'] as num) +
                  2000 * i +
                  (gap && i > 900 ? 10000 : 0),
              if (hot && i == 900) 'thermal': 'fair',
            },
        ];
        soakProbe.writeAsStringSync('${records.map(jsonEncode).join('\n')}\n');
        soakLog.writeAsStringSync(
          '${records.map((r) => '[ENERGY_PROBE] ${jsonEncode(Map.of(r)..remove('hostTime'))}').join('\n')}\n',
        );
      }

      final identity = CreatorCardIdentity(
        visualId: alpha.id,
        programHash: ReadinessTool.programHash(alpha),
        revision: visualRevision(alpha),
        buildHash: buildHash(),
        framesPerSecond: alpha.framesPerSecond,
        reactive: alpha.reactivity != CreatorReactivity.none,
        native: alpha.isNative,
        role: alpha.role.name,
        controls: alpha.controls.toMap(),
        modifiers: alpha.modifierDefaults,
      );
      final contract =
          jsonDecode(
                File(
                  '${catalog.path}/readiness/energy_contract.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      Map<String, Object?> profiles() => {
        'iPad13,4': {
          'operatingSystem': 'iPadOS 27',
          'systemVersion': '27.0',
          'surfaceWidth': 900,
          'surfaceHeight': 1296,
          'scope': 'iPad',
          'calibrationAnchors': [
            {
              'identity': {
                'visualId': alpha.id,
                'programHash': identity.programHash,
                'revision': identity.revision,
                'buildHash': identity.buildHash,
                'framesPerSecond': alpha.framesPerSecond,
                'reactive': identity.reactive,
                'native': alpha.isNative,
                'role': alpha.role.name,
                'controls': alpha.controls.toMap(),
                'modifiers': alpha.modifierDefaults,
              },
              'card': anchorCard,
              'soak': {
                'console': ref(soakLog),
                'probe': ref(soakProbe),
                'minimumBrightness': 0.5,
              },
            },
          ],
        },
      };
      CreatorCardVerdict verdict({
        Map<String, Object?>? card,
        Map<String, Object?>? devices,
        bool referenceOnly = false,
      }) => validateCreatorDeviceCard(
        card: card ?? anchorCard,
        identity: identity,
        contractCopy: contract,
        profileLabel: 'valores iniciales',
        deviceProfiles: devices ?? profiles(),
        referenceOnly: referenceOnly,
      );
      writeSoak();
      expect(verdict().status, 'within');
      expect(verdict().scope, 'iPad, conectado, brillo ≤ 50%, visual aislado');
      expect(verdict(referenceOnly: true).status, 'pending');
      final stale = profiles();
      soakProbe.writeAsStringSync('altered');
      expect(verdict(devices: stale).detail, contains('alterados'));
      writeSoak(count: 1000);
      expect(verdict().detail, contains('más corta'));
      writeSoak(hot: true);
      expect(verdict().detail, contains('condición térmica'));
      writeSoak(gap: true);
      expect(verdict().detail, contains('hueco'));
      writeSoak();
      // An isolated overlay can use the background load envelope, but the
      // anchor keeps its real background role in its raw identity.
      final overlayRows = writeRows(
        alpha,
        device: ipad,
        surfacePx: (900, 1296),
        record: {'brightness': 0.5},
        creator: {'role': 'overlay'},
        row: {'role': 'overlay'},
      );
      expect(importCards(overlayRows), 0);
      final overlayIdentity = CreatorCardIdentity(
        visualId: identity.visualId,
        programHash: identity.programHash,
        revision: identity.revision,
        buildHash: identity.buildHash,
        framesPerSecond: identity.framesPerSecond,
        reactive: identity.reactive,
        native: identity.native,
        role: 'overlay',
        controls: identity.controls,
        modifiers: identity.modifiers,
      );
      CreatorCardVerdict crossRole(Map<String, Object?> devices) =>
          validateCreatorDeviceCard(
            card: currentCard(),
            identity: overlayIdentity,
            contractCopy: contract,
            profileLabel: 'synthetic overlay',
            deviceProfiles: devices,
          );
      expect(crossRole(profiles()).status, 'within');
      final forgedRole = profiles();
      (((forgedRole['iPad13,4'] as Map)['calibrationAnchors'] as List).single
              as Map)['identity']['role'] =
          'overlay';
      expect(crossRole(forgedRole).status, 'pending');
      final otherCadence = profiles();
      (((otherCadence['iPad13,4'] as Map)['calibrationAnchors'] as List).single
              as Map)['identity']['framesPerSecond'] =
          30;
      expect(crossRole(otherCadence).status, 'pending');
      // A lower GPU does not compensate for a higher CPU load.
      final candidate = writeRows(
        alpha,
        device: ipad,
        surfacePx: (900, 1296),
        record: {'brightness': 0.5},
        row: {
          'runnerEPercent': 35.0,
          'gpuAppMsPerSecond': 100.0,
          'gpuAppMsPerPublishedFrame': 100.0 / alpha.framesPerSecond,
        },
      );
      expect(importCards(candidate), 0);
      expect(
        verdict(card: currentCard()).detail,
        contains('otra ancla sostenida'),
      );
    },
  );

  test(
    'raw trace and measured pixels are required; changing a trace cannot certify',
    () {
      expect(run(['prepare', '--evidence', evidence.path]), 0);
      void pending(File rows, String detail, {bool import = true}) {
        if (import) expect(importCards(rows), 0);
        expect(run(['prepare', '--evidence', evidence.path]), 0);
        expect(entry('alpha')['state'], 'pendingEvidence');
        expect(check('alpha', 'deviceCard')['detail'], contains(detail));
      }

      final zero = writeRows(
        alpha,
        row: {
          'gpuAppMsPerSecond': 0.0,
          'gpuAppMsPerPublishedFrame': 0.0,
          'runnerEPercent': 0.0,
          'runnerSPercent': 0.0,
          'renderThreadPercent': 0.0,
        },
      );
      final payload =
          jsonDecode(zero.readAsStringSync()) as Map<String, dynamic>;
      payload.remove('traceEvidence');
      zero.writeAsStringSync('${jsonEncode(payload)}\n');
      pending(zero, 'sin muestras originales');
      pending(
        writeRows(
          alpha,
          surfacePx: null,
          row: {
            'surfacePx': {'width': 664, 'height': 1440},
          },
        ),
        'sin superficie medida',
      );
      final rows = writeRows(alpha);
      expect(importCards(rows), 0);
      final trace = File(
        '${repo.path}/probe/$probeIndex-alpha-trace-samples.json',
      );
      trace.writeAsStringSync('${trace.readAsStringSync()} ');
      pending(rows, 'muestras del trace cambiaron', import: false);
    },
  );

  test('the log must measure the full profile, not only its default label', () {
    expect(run(['prepare', '--evidence', evidence.path]), 0);
    final original = jsonDecode(writeRows(alpha).readAsStringSync()) as Map;
    final identity = Map<String, Object?>.from(original['creator'] as Map);
    final profile = Map<String, Object?>.from(identity['profile'] as Map);
    profile['controls'] = {...alpha.controls.toMap(), 'detail': 2.0};
    identity['profile'] = profile;
    final rows = writeRows(alpha, record: {'creator': identity});
    expect(importCards(rows), 0);
    expect(run(['prepare', '--evidence', evidence.path]), 0);
    expect(entry('alpha')['state'], 'pendingEvidence');
    expect(
      check('alpha', 'deviceCard')['detail'],
      contains('otro visual, build o perfil'),
    );
  });

  test('the contract copy is DATA with provenance and the values consumed', () {
    final copy =
        jsonDecode(
              File(
                '${catalog.path}/readiness/energy_contract.json',
              ).readAsStringSync(),
            )
            as Map;
    expect(copy['revision'], 'scene-energy-budget-v1');
    expect(copy['semanticHash'], hasLength(64));
    expect(copy['source'], contains('contract/scene_energy_budget_v1.json'));
    expect(copy['sourceFileSha256'], hasLength(64));
    final values = copy['values'] as Map;
    expect(
      ((values['slotCeilings'] as Map)['background'] as Map)['gpuMsPerSecond'],
      839.4,
    );
    expect((values['protocol'] as Map)['measurementWarmupSeconds'], 15);
    expect((values['reference'] as Map)['identifier'], 'iPhone15,2');
    // Same file, same hash; another formatting, same semantic hash.
    final live = File('${repo.path}/contract/scene_energy_budget_v1.json');
    final pretty = const JsonEncoder.withIndent(
      '    ',
    ).convert(jsonDecode(live.readAsStringSync()));
    live.writeAsStringSync(pretty);
    expect(run(['contract', 'import', live.path]), 0, reason: err.toString());
    final again =
        jsonDecode(
              File(
                '${catalog.path}/readiness/energy_contract.json',
              ).readAsStringSync(),
            )
            as Map;
    expect(again['semanticHash'], copy['semanticHash']);
    // The manifest carries the contract stamp: a new copy is a new build.
    final before = buildHash();
    writeContract(backgroundGpu: 1.0);
    expect(run(['contract', 'import', live.path]), 0, reason: err.toString());
    expect(buildHash(), isNot(before));
  });

  test('status reports drift of the drawing and of the engine', () {
    expect(
      run(['prepare', '--evidence', evidence.path]),
      0,
      reason: err.toString(),
    );
    expect(run(['status']), 0, reason: err.toString());
    expect(out.toString(), contains('pendingEvidence 4'));
    // The drawing changed: its evidence no longer applies.
    writeCatalog([
      CreatorVisualDefinition(
        id: 'alpha',
        name: 'Alpha',
        nativeSource: 'class Visual final : public Scene { int y = m.capas; };',
        nativeBuild: {
          'abi': 1,
          'hash': 'hash-alpha-2',
          'imageHashes': <String, String>{},
          'materials': <String>[],
          'sdkHash': sdk,
        },
        framesPerSecond: 60,
        modifiers: [
          CreatorModifier.steps('capas', 'Capas', min: 1, max: 40, value: 5),
        ],
      ),
      beta,
      plasma,
      synthwave,
    ]);
    expect(run(['status']), 1);
    expect(out.toString(), contains('alpha: unknown'));
    expect(out.toString(), contains('cambiados desde la comprobación: 1'));
    // Stale logs are refused: the registry must never mix catalogs.
    expect(run(['prepare', '--evidence', evidence.path]), 1);
    expect(err.toString(), contains('otro catálogo'));
    writeChecks();
    expect(
      run(['prepare', '--evidence', evidence.path]),
      0,
      reason: err.toString(),
    );
    writeEngine(runtime: 'swift v3');
    expect(run(['status']), 1);
    expect(out.toString(), contains('motor DISTINTO'));
    expect(out.toString(), contains('manifiesto de build'));
  });

  test('the creative author comes from the attribution file, git apart', () {
    File('${catalog.path}/readiness/attribution.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'schemaVersion': 1,
          'source': {'description': 'SYNTHETIC attribution fixture'},
          'visuals': {
            'alpha': {'author': 'Franco david', 'date': '2026-10-04'},
          },
        }),
      );
    expect(
      run(['prepare', '--evidence', evidence.path]),
      0,
      reason: err.toString(),
    );
    expect((entry('alpha')['origin'] as Map)['author'], 'Franco david');
    expect(
      (entry('alpha')['origin'] as Map)['authorSource'],
      'attribution.json',
    );
    expect((entry('beta')['origin'] as Map)['author'], '');
    expect(
      run(['status', '--author', 'Franco david']),
      0,
      reason: err.toString(),
    );
    expect(out.toString(), contains('Franco david (1)'));
  });

  group('links', () {
    void git(List<String> args) {
      final result = Process.runSync('git', ['-C', repo.path, ...args]);
      if (result.exitCode != 0)
        throw StateError('git ${args.join(' ')}: ${result.stderr}');
    }

    setUp(() {
      git(['init', '-q']);
      git(['config', 'user.email', 'test@example.com']);
      git(['config', 'user.name', 'Test']);
      git(['add', '.']);
      git(['commit', '-q', '-m', 'base']);
      expect(
        run(['prepare', '--evidence', evidence.path]),
        0,
        reason: err.toString(),
      );
    });

    Map<String, Object?> links() =>
        jsonDecode(
              File(
                '${catalog.path}/readiness/revision_links.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    List<Map<String, Object?>> linkList() => [
      for (final l in links()['links'] as List) l as Map<String, Object?>,
    ];

    test('a cadence-only change is proposed, never reviewed by the tool', () {
      final slower = CreatorVisualDefinition(
        id: 'alpha',
        name: 'Alpha',
        nativeSource: alpha.nativeSource,
        nativeBuild: alpha.nativeBuild,
        framesPerSecond: 30,
        modifiers: alpha.modifiers,
      );
      writeCatalog([slower, beta, plasma, synthwave]);
      writeChecks();
      expect(
        run(['prepare', '--evidence', evidence.path]),
        0,
        reason: err.toString(),
      );
      expect(
        run(['links', 'propose', '--base', 'HEAD']),
        0,
        reason: err.toString(),
      );
      final link = linkList().single;
      expect(link['visualId'], 'alpha');
      expect(link['from'], visualRevision(alpha));
      expect(link['to'], visualRevision(slower));
      expect(link['status'], 'proposed');
      expect(link['kind'], 'fpsOnly');
      expect((link['evidence'] as Map)['temporalRule30_60'], 'pass');
      expect(link['summary'], contains('suavidad'));
      expect(
        RevisionLinks.parse(
          jsonEncode(links()),
        ).inherits('alpha', visualRevision(slower)),
        isFalse,
      );
      // Review requires a person and the revision on screen.
      expect(
        run([
          'links',
          'review',
          'alpha',
          '--from',
          link['from'] as String,
          '--to',
          'nope',
          '--reviewer',
          'Katy',
        ]),
        1,
      );
      expect(err.toString(), contains('revisión actual'));
      expect(
        run([
          'links',
          'review',
          'alpha',
          '--from',
          link['from'] as String,
          '--to',
          link['to'] as String,
          '--reviewer',
          'readiness',
        ]),
        1,
      );
      expect(
        run([
          'links',
          'review',
          'alpha',
          '--from',
          link['from'] as String,
          '--to',
          link['to'] as String,
          '--reviewer',
          'Katy',
          '--note',
          'A/B visto',
        ]),
        0,
        reason: err.toString(),
      );
      final reviewed = linkList().single;
      expect(reviewed['status'], 'reviewed');
      expect(reviewed['reviewer'], 'Katy');
      expect(
        RevisionLinks.parse(
          jsonEncode(links()),
        ).equivalents('alpha', visualRevision(slower)),
        [visualRevision(slower), visualRevision(alpha)],
      );
      // A new proposal never overwrites the human decision.
      expect(
        run(['links', 'propose', '--base', 'HEAD']),
        0,
        reason: err.toString(),
      );
      expect(linkList().single['status'], 'reviewed');
      expect(run(['links', 'status']), 0);
      expect(out.toString(), contains('reviewed 1'));
    });

    test(
      'a code change needs pixel evidence; a visible change is a revote',
      () {
        final changed = CreatorVisualDefinition(
          id: 'alpha',
          name: 'Alpha',
          nativeSource:
              'class Visual final : public Scene { int z = m.capas; };',
          nativeBuild: {
            'abi': 1,
            'hash': 'hash-alpha-2',
            'imageHashes': <String, String>{},
            'materials': <String>[],
            'sdkHash': sdk,
          },
          framesPerSecond: 60,
          modifiers: alpha.modifiers,
        );
        writeCatalog([changed, beta, plasma, synthwave]);
        writeChecks();
        expect(
          run(['prepare', '--evidence', evidence.path]),
          0,
          reason: err.toString(),
        );
        // Without captures: no evidence, no link.
        expect(
          run(['links', 'propose', '--base', 'HEAD']),
          0,
          reason: err.toString(),
        );
        expect(linkList(), isEmpty);
        expect(out.toString(), contains('sin evidencia 1'));
        // Identical captures at the same instants: proposed with parity.
        final captures = Directory('${repo.path}/captures');
        for (final side in ['base', 'current']) {
          for (final t in ['1000', '3000']) {
            File('${captures.path}/$side/alpha_t$t.png')
              ..createSync(recursive: true)
              ..writeAsBytesSync(
                _png(4, 2, (x, y) => [x * 40, y * 90, 7, 255]),
              );
          }
        }
        expect(
          run([
            'links',
            'propose',
            '--base',
            'HEAD',
            '--captures',
            captures.path,
          ]),
          0,
          reason: err.toString(),
        );
        var link = linkList().single;
        expect(link['status'], 'proposed');
        expect(link['kind'], 'pixelParity');
        expect((link['evidence'] as Map)['changedFields'], ['nativeSource']);
        expect(((link['evidence'] as Map)['pixelParity'] as Map)['frames'], 2);
        // A visible difference: rejected by evidence, the team votes again.
        File(
          '${captures.path}/current/alpha_t3000.png',
        ).writeAsBytesSync(_png(4, 2, (x, y) => [255 - x * 40, 0, 200, 255]));
        expect(
          run([
            'links',
            'propose',
            '--base',
            'HEAD',
            '--captures',
            captures.path,
          ]),
          0,
          reason: err.toString(),
        );
        link = linkList().single;
        expect(link['status'], 'rejected');
        expect(link['kind'], 'visibleChange');
        expect(
          RevisionLinks.parse(
            jsonEncode(links()),
          ).inherits('alpha', visualRevision(changed)),
          isFalse,
        );
      },
    );
  });
}

/// Minimal RGBA PNG (filter 0), enough for the parity reader.
List<int> _png(int width, int height, List<int> Function(int x, int y) pixel) {
  final raw = <int>[];
  for (var y = 0; y < height; y++) {
    raw.add(0);
    for (var x = 0; x < width; x++) {
      raw.addAll(pixel(x, y));
    }
  }
  List<int> chunk(String type, List<int> data) {
    final typeBytes = ascii.encode(type);
    final crc = _crc32([...typeBytes, ...data]);
    return [..._u32(data.length), ...typeBytes, ...data, ..._u32(crc)];
  }

  return [
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    ...chunk('IHDR', [..._u32(width), ..._u32(height), 8, 6, 0, 0, 0]),
    ...chunk('IDAT', zlib.encode(raw)),
    ...chunk('IEND', []),
  ];
}

List<int> _u32(int value) => [
  (value >> 24) & 0xff,
  (value >> 16) & 0xff,
  (value >> 8) & 0xff,
  value & 0xff,
];

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
