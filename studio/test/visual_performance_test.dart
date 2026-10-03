import 'package:audiovisual_creator/performance/visual_performance.dart';
import 'package:audiovisual_creator/performance/visual_performance_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_compositor/scene_compositor.dart';

class _Source implements VisualPerformanceSource {
  _Source({this.nativeSurface = false});

  @override
  final bool nativeSurface;
  bool measuringOn = false;
  AndroidCreatorRenderStats? android;
  Map<Object?, Object?>? stats;
  Map<Object?, Object?>? summary;
  PlatformException? stopError;
  int started = 0;
  final stopped = <Map<Object?, Object?>>[];
  final cancelled = <Map<Object?, Object?>>[];

  @override
  set measuring(bool value) => measuringOn = value;

  @override
  AndroidCreatorRenderStats? get androidStats => android;

  @override
  Future<Map<Object?, Object?>?> readSurfaceStats() async => stats;

  @override
  Future<Map<Object?, Object?>?> startProbe() async => {
    'probeToken': 'probe-${++started}',
  };

  @override
  Future<Map<Object?, Object?>?> stopProbe(
    Map<Object?, Object?> identity,
  ) async {
    stopped.add(identity);
    if (stopError case final PlatformException error) throw error;
    return summary;
  }

  @override
  Future<void> cancelProbe(Map<Object?, Object?> identity) async {
    cancelled.add(identity);
  }
}

class _Clock {
  int wall = 0;
  int? cpu = 0;

  /// One second passes and the process uses [cpuMillis] of CPU.
  void advance(int cpuMillis) {
    wall += 1000000;
    cpu = cpu! + cpuMillis * 1000;
  }
}

AndroidCreatorRenderStats _stats(
  int frames, {
  int session = 1,
  int? cpu,
  double simulation = 0,
}) => AndroidCreatorRenderStats(
  sessionId: session,
  frames: frames,
  cpuMicros: cpu,
  simulationMicros: simulation,
);

void main() {
  late _Clock clock;
  late VisualActivity activity;

  setUp(() {
    clock = _Clock();
    activity = VisualActivity.playing;
  });

  VisualPerformanceMonitor monitor(_Source source, {int? fps = 30}) =>
      VisualPerformanceMonitor(
        source: source,
        activity: () => activity,
        targetFramesPerSecond: () => fps,
        processCpuMicros: () => clock.cpu,
        wallMicros: () => clock.wall,
        cores: 8,
        // Ticks are driven by hand.
        interval: const Duration(hours: 1),
      );

  Future<VisualPerformanceMonitor> started(_Source source) async {
    final result = monitor(source)..start();
    await pumpEventQueue();
    return result;
  }

  test('Android: CPU, FPS and visual CPU per frame are deltas', () async {
    final source = _Source()..android = _stats(0, cpu: 0);
    final performance = await started(source);
    expect(source.measuringOn, isTrue);
    expect(performance.sample.value!.processCpuPercent, isNull);

    clock.advance(400);
    source.android = _stats(30, cpu: 120000, simulation: 30000);
    await performance.tick();
    final sample = performance.sample.value!;
    expect(sample.processCpuPercent, closeTo(40, 0.01));
    expect(sample.framesPerSecond, closeTo(30, 0.01));
    expect(sample.visualCpuMsPerFrame, closeTo(4, 0.01));
    expect(sample.simulationMsPerFrame, closeTo(1, 0.01));
    expect(sample.frameBudgetMs, closeTo(33.33, 0.01));

    // A new session (other visual) starts from zero: never mixed.
    clock.advance(400);
    source.android = _stats(5, session: 2, cpu: 9000);
    await performance.tick();
    expect(performance.sample.value!.framesPerSecond, isNull);
    expect(performance.sample.value!.visualCpuMsPerFrame, isNull);
    expect(performance.sample.value!.processCpuPercent, closeTo(40, 0.01));

    performance.dispose();
    expect(source.measuringOn, isFalse);
  });

  test('the paused studio is the baseline of what the visual adds', () async {
    final source = _Source();
    activity = VisualActivity.paused;
    final performance = await started(source);

    clock.advance(100);
    await performance.tick();
    expect(performance.sample.value!.pausedCpuPercent, closeTo(10, 0.01));

    // The first playing window still contains paused time: not compared.
    activity = VisualActivity.playing;
    clock.advance(300);
    await performance.tick();
    expect(performance.sample.value!.processCpuPercent, closeTo(30, 0.01));
    expect(performance.sample.value!.visualCpuPercent, isNull);

    clock.advance(450);
    await performance.tick();
    expect(performance.sample.value!.visualCpuPercent, closeTo(35, 0.01));

    // Loading is neither paused nor playing: it never moves the baseline.
    activity = VisualActivity.busy;
    clock.advance(900);
    await performance.tick();
    clock.advance(900);
    await performance.tick();
    expect(performance.sample.value!.pausedCpuPercent, closeTo(10, 0.01));
    expect(performance.sample.value!.visualCpuPercent, isNull);
    performance.dispose();
  });

  test('iOS: a probe per second gives frame time and stutters', () async {
    final source = _Source(nativeSurface: true)
      ..stats = {
        'sessionId': 'a',
        'publishedFrameCount': 100,
        'sampleTimeSeconds': 10.0,
        'creatorPrograms': [
          {
            'instance': 1,
            'updates': 100,
            'simulationAverageMicros': 1000.0,
            'framesPerSecond': 60,
            'thermalState': 1,
          },
        ],
      };
    final performance = await started(source);
    expect(source.started, 1);

    clock.advance(500);
    source
      ..summary = {
        'sampleCount': 58,
        'averageFrameMilliseconds': 6.5,
        'p95FrameMilliseconds': 12.0,
        'jankPercent': 1.5,
        'targetFramesPerSecond': 60,
      }
      ..stats = {
        'sessionId': 'a',
        'publishedFrameCount': 158,
        'sampleTimeSeconds': 11.0,
        'creatorPrograms': [
          {
            'instance': 1,
            'updates': 158,
            'simulationAverageMicros': 1200.0,
            'framesPerSecond': 60,
            'thermalState': 1,
          },
        ],
      };
    await performance.tick();
    final sample = performance.sample.value!;
    expect(source.stopped.single['probeToken'], 'probe-1');
    expect(source.started, 2);
    expect(sample.framesPerSecond, closeTo(58, 0.01));
    expect(sample.targetFramesPerSecond, 60);
    expect(sample.frameAverageMs, 6.5);
    expect(sample.frameP95Ms, 12.0);
    expect(sample.jankPercent, 1.5);
    expect(sample.thermalState, 1);
    // (158 × 1200 − 100 × 1000) / 58 updates = 1.545 ms.
    expect(sample.simulationMsPerFrame, closeTo(1.545, 0.001));

    // An edit invalidated the window: frame time is dropped, FPS stays.
    clock.advance(500);
    source
      ..stopError = PlatformException(code: 'probe_invalidated')
      ..stats = {
        ...source.stats!,
        'publishedFrameCount': 218,
        'sampleTimeSeconds': 12.0,
      };
    await performance.tick();
    expect(performance.sample.value!.frameAverageMs, isNull);
    expect(performance.sample.value!.framesPerSecond, isNotNull);

    // Paused: the open probe is stopped and no new one is started.
    activity = VisualActivity.paused;
    source.stopError = null;
    clock.advance(100);
    await performance.tick();
    expect(source.started, 3);
    expect(performance.sample.value!.activity, VisualActivity.paused);
    performance.dispose();
  });

  test('a new visual or stopping cancels the open probe', () async {
    final source = _Source(nativeSurface: true);
    final performance = await started(source);
    performance.restart();
    await pumpEventQueue();
    expect(source.cancelled.single['probeToken'], 'probe-1');

    clock.advance(100);
    await performance.tick();
    performance.stop();
    await pumpEventQueue();
    expect(source.cancelled.last['probeToken'], 'probe-2');
    expect(source.measuringOn, isFalse);
    performance.dispose();
  });

  testWidgets('overlay: summary, details and honest GPU row', (tester) async {
    final sample = ValueNotifier<VisualPerformanceSample?>(
      const VisualPerformanceSample(
        nativeSurface: false,
        activity: VisualActivity.playing,
        cores: 8,
        processCpuPercent: 34,
        pausedCpuPercent: 12,
        visualCpuPercent: 22,
        framesPerSecond: 29.6,
        targetFramesPerSecond: 30,
        visualCpuMsPerFrame: 4.2,
        simulationMsPerFrame: 0.018,
      ),
    );
    addTearDown(sample.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: VisualPerformanceOverlay(sample: sample, debugBuild: false),
          ),
        ),
      ),
    );
    expect(find.textContaining('CPU 34%'), findsOneWidget);
    expect(find.textContaining('30/30 FPS'), findsOneWidget);
    expect(find.text('GPU'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('performance-toggle')));
    await tester.pump();
    expect(find.text('RENDIMIENTO · Android'), findsOneWidget);
    expect(find.text('≈ +22% (pausa 12%)'), findsOneWidget);
    expect(find.text('4.2 de 33.3 ms'), findsOneWidget);
    expect(find.text('no medible en Android'), findsOneWidget);
    expect(find.text('0.02 ms'), findsOneWidget);

    sample.value = const VisualPerformanceSample(
      nativeSurface: true,
      activity: VisualActivity.playing,
      cores: 6,
      processCpuPercent: 51,
      framesPerSecond: 60,
      targetFramesPerSecond: 60,
      frameAverageMs: 6.1,
      frameP95Ms: 9.8,
      jankPercent: 0,
      thermalState: 2,
    );
    await tester.pump();
    expect(find.text('RENDIMIENTO · iPhone'), findsOneWidget);
    expect(find.text('6.1 de 16.7 ms'), findsOneWidget);
    expect(find.text('incluida en Cuadro'), findsOneWidget);
    expect(find.text('caliente (baja velocidad)'), findsOneWidget);
    expect(find.text('pausa 2 s para comparar'), findsOneWidget);

    sample.value = const VisualPerformanceSample(
      nativeSurface: true,
      activity: VisualActivity.paused,
      cores: 6,
      processCpuPercent: 9,
    );
    await tester.pump();
    expect(find.text('base del estudio'), findsOneWidget);
    expect(find.text('en pausa'), findsOneWidget);
    expect(find.textContaining('Modo debug'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overlay warns that debug builds read high', (tester) async {
    final sample = ValueNotifier<VisualPerformanceSample?>(null);
    addTearDown(sample.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: VisualPerformanceOverlay(sample: sample, debugBuild: true),
          ),
        ),
      ),
    );
    expect(find.textContaining('· debug'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('performance-toggle')));
    await tester.pump();
    expect(find.textContaining('Modo debug'), findsOneWidget);
    expect(find.text('Midiendo…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
