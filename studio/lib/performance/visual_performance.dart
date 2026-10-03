import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:scene_compositor/scene_compositor.dart';

/// What the studio is doing with the visual during a sample.
enum VisualActivity {
  /// Frames are being drawn.
  playing,

  /// The user paused a loaded visual: only the studio itself runs.
  paused,

  /// Loading, failed or in the background: neither cost is representative.
  busy,
}

/// One second of live cost for the visual on screen. A null field means it
/// can't be measured on this platform or isn't available yet: the overlay
/// shows "—" instead of guessing.
@immutable
class VisualPerformanceSample {
  const VisualPerformanceSample({
    required this.nativeSurface,
    required this.activity,
    required this.cores,
    this.processCpuPercent,
    this.pausedCpuPercent,
    this.visualCpuPercent,
    this.framesPerSecond,
    this.targetFramesPerSecond,
    this.frameAverageMs,
    this.frameP95Ms,
    this.jankPercent,
    this.visualCpuMsPerFrame,
    this.simulationMsPerFrame,
    this.thermalState,
  });

  /// iOS native compositor (true) or the Android Flutter renderer (false).
  final bool nativeSurface;
  final VisualActivity activity;
  final int cores;

  /// CPU of the whole Creator process; 100 = one full core.
  final double? processCpuPercent;

  /// The same CPU measured with the visual paused: the studio's own cost.
  final double? pausedCpuPercent;

  /// Playing minus paused: what playing the visual adds (its rendering plus
  /// the signal replay that feeds it).
  final double? visualCpuPercent;
  final double? framesPerSecond;
  final int? targetFramesPerSecond;

  /// iOS: time to render one frame on the native render queue, CPU work plus
  /// waiting for the GPU passes (they are synchronous). Not split yet.
  final double? frameAverageMs;
  final double? frameP95Ms;

  /// iOS: share of frames that overran 1.1× their time budget.
  final double? jankPercent;

  /// Android: CPU time of the Dart thread recording one frame.
  final double? visualCpuMsPerFrame;

  /// Native visuals: time of the C++ simulation step per frame.
  final double? simulationMsPerFrame;

  /// iOS native visuals: 0 normal, 1 fair, 2 serious, 3 critical.
  final int? thermalState;

  bool get playing => activity == VisualActivity.playing;

  /// Time one frame may take without dropping below the target rate.
  double? get frameBudgetMs {
    final target = targetFramesPerSecond;
    return target == null || target <= 0 ? null : 1000 / target;
  }
}

/// What the monitor needs from the compositor. The studio adapts its
/// [SceneCompositorController]; tests supply a fake.
abstract interface class VisualPerformanceSource {
  bool get nativeSurface;

  /// Turns the renderer's own per-frame accounting on or off.
  set measuring(bool value);
  Future<Map<Object?, Object?>?> readSurfaceStats();
  Future<Map<Object?, Object?>?> startProbe();
  Future<Map<Object?, Object?>?> stopProbe(Map<Object?, Object?> identity);
  Future<void> cancelProbe(Map<Object?, Object?> identity);
  AndroidCreatorRenderStats? get androidStats;
}

class ControllerPerformanceSource implements VisualPerformanceSource {
  ControllerPerformanceSource(this.controller);

  final SceneCompositorController controller;

  @override
  bool get nativeSurface =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  set measuring(bool value) => controller.measureRenderCost = value;

  @override
  Future<Map<Object?, Object?>?> readSurfaceStats() =>
      controller.readSurfaceStats();

  @override
  Future<Map<Object?, Object?>?> startProbe() =>
      controller.startPerformanceProbe();

  @override
  Future<Map<Object?, Object?>?> stopProbe(Map<Object?, Object?> identity) =>
      controller.stopPerformanceProbe(identity);

  @override
  Future<void> cancelProbe(Map<Object?, Object?> identity) =>
      controller.cancelPerformanceProbe(identity);

  @override
  AndroidCreatorRenderStats? get androidStats => controller.androidRenderStats;
}

/// Samples the visual's cost once per [interval] while started. Every
/// number is a delta between two readings of the same surface session, so a
/// visual change, reset or invalidated window is dropped, never mixed.
class VisualPerformanceMonitor {
  VisualPerformanceMonitor({
    required this.source,
    required this.activity,
    required this.targetFramesPerSecond,
    int? Function()? processCpuMicros,
    int Function()? wallMicros,
    int? cores,
    this.interval = const Duration(seconds: 1),
  }) : _processCpuMicros =
           processCpuMicros ?? (() => CpuClock.instance?.processMicros),
       _wallMicros = wallMicros ?? _stopwatchMicros,
       cores = cores ?? Platform.numberOfProcessors;

  final VisualPerformanceSource source;
  final VisualActivity Function() activity;
  final int? Function() targetFramesPerSecond;
  final Duration interval;
  final int cores;
  final int? Function() _processCpuMicros;
  final int Function() _wallMicros;
  final ValueNotifier<VisualPerformanceSample?> sample =
      ValueNotifier<VisualPerformanceSample?>(null);

  static const _callTimeout = Duration(seconds: 3);
  static final Stopwatch _clock = Stopwatch()..start();
  static int _stopwatchMicros() => _clock.elapsedMicroseconds;

  Timer? _timer;
  bool _busy = false;
  bool _disposed = false;
  int? _lastWall;
  int? _lastCpu;
  VisualActivity? _lastActivity;
  double? _pausedCpu;
  Map<Object?, Object?>? _probe;
  Object? _surfaceSession;
  int? _surfaceFrames;
  double? _surfaceTime;
  Object? _programInstance;
  int? _programUpdates;
  double? _programSimulationTotal;
  AndroidCreatorRenderStats? _androidStats;
  int? _androidWall;

  bool get running => _timer != null;

  void start() {
    if (_disposed || _timer != null) return;
    source.measuring = true;
    _timer = Timer.periodic(interval, (_) => unawaited(tick()));
    unawaited(tick());
  }

  void stop() {
    if (_timer == null) return;
    _timer!.cancel();
    _timer = null;
    source.measuring = false;
    restart();
    _lastWall = null;
    _lastCpu = null;
  }

  /// Forgets the per-visual baselines (new visual, reset) and releases the
  /// native probe so its frame log doesn't keep growing. The process CPU
  /// keeps running and the paused CPU is kept: it is the studio's cost.
  void restart() {
    final probe = _probe;
    _probe = null;
    if (probe != null) {
      unawaited(
        source
            .cancelProbe(probe)
            .timeout(_callTimeout)
            .catchError((Object _) {}),
      );
    }
    _lastActivity = null;
    _surfaceSession = null;
    _surfaceFrames = null;
    _surfaceTime = null;
    _programInstance = null;
    _programUpdates = null;
    _programSimulationTotal = null;
    _androidStats = null;
    _androidWall = null;
  }

  void dispose() {
    stop();
    _disposed = true;
    sample.dispose();
  }

  @visibleForTesting
  Future<void> tick() async {
    if (_busy || _disposed) return;
    _busy = true;
    try {
      final now = _wallMicros();
      final cpu = _processCpuMicros();
      final current = activity();
      double? cpuPercent;
      final lastWall = _lastWall;
      final lastCpu = _lastCpu;
      if (cpu != null && lastCpu != null && lastWall != null) {
        final wall = now - lastWall;
        final used = cpu - lastCpu;
        // Very short or very long windows give misleading percentages.
        if (wall >= 250000 && wall <= 5000000 && used >= 0) {
          cpuPercent = used * 100 / wall;
        }
      }
      // A window that started paused and ended playing (or loading, or a
      // new visual) mixes costs: it is shown, but never compared.
      final settled = _lastActivity == current;
      _lastWall = now;
      _lastCpu = cpu;
      _lastActivity = current;
      if (current == VisualActivity.paused && settled && cpuPercent != null) {
        final paused = _pausedCpu;
        _pausedCpu =
            paused == null ? cpuPercent : paused * 0.7 + cpuPercent * 0.3;
      }
      final paused = _pausedCpu;
      final visualCpu =
          current == VisualActivity.playing &&
                  settled &&
                  cpuPercent != null &&
                  paused != null
              ? (cpuPercent - paused).clamp(0.0, double.infinity).toDouble()
              : null;
      final next =
          source.nativeSurface
              ? await _sampleNative(current, cpuPercent, visualCpu)
              : _sampleAndroid(now, current, cpuPercent, visualCpu);
      if (!_disposed) sample.value = next;
    } finally {
      _busy = false;
    }
  }

  Future<VisualPerformanceSample> _sampleNative(
    VisualActivity current,
    double? cpuPercent,
    double? visualCpu,
  ) async {
    Map<Object?, Object?>? summary;
    final identity = _probe;
    _probe = null;
    if (identity != null) {
      try {
        summary = await source.stopProbe(identity).timeout(_callTimeout);
      } on PlatformException {
        // The surface changed while measured (edit, pause, resize): skip.
      } on TimeoutException {
        // Leave the window empty rather than block the overlay.
      }
    }
    // Only probe while frames are being drawn: a paused probe records
    // nothing and a forgotten one keeps logging every frame natively.
    if (current == VisualActivity.playing && running) {
      try {
        final probe = await source.startProbe().timeout(_callTimeout);
        if (running) {
          _probe = probe;
        } else if (probe != null) {
          // Stopped while starting: don't leave it logging frames.
          unawaited(
            source
                .cancelProbe(probe)
                .timeout(_callTimeout)
                .catchError((Object _) {}),
          );
        }
      } on PlatformException {
        _probe = null;
      } on TimeoutException {
        _probe = null;
      }
    }
    Map<Object?, Object?>? stats;
    try {
      stats = await source.readSurfaceStats().timeout(_callTimeout);
    } on PlatformException {
      stats = null;
    } on TimeoutException {
      stats = null;
    }

    double? fps;
    final session = stats?['sessionId'];
    final frames = _int(stats?['publishedFrameCount']);
    final time = _double(stats?['sampleTimeSeconds']);
    final lastFrames = _surfaceFrames;
    final lastTime = _surfaceTime;
    if (session != null &&
        session == _surfaceSession &&
        frames != null &&
        time != null &&
        lastFrames != null &&
        lastTime != null) {
      final seconds = time - lastTime;
      final drawn = frames - lastFrames;
      if (seconds > 0.2 && drawn >= 0) fps = drawn / seconds;
    }
    _surfaceSession = session;
    _surfaceFrames = frames;
    _surfaceTime = time;

    // Authored native visuals report their simulation, frame cap and the
    // device's thermal state; shader visuals report nothing here.
    final programs = stats?['creatorPrograms'];
    final metrics =
        programs is List
            ? programs.whereType<Map<Object?, Object?>>().firstOrNull
            : null;
    double? simulation;
    final instance = metrics?['instance'];
    final updates = _int(metrics?['updates']);
    final average = _double(metrics?['simulationAverageMicros']);
    final total = updates != null && average != null ? updates * average : null;
    final lastUpdates = _programUpdates;
    final lastTotal = _programSimulationTotal;
    if (instance != null &&
        instance == _programInstance &&
        updates != null &&
        total != null &&
        lastUpdates != null &&
        lastTotal != null &&
        updates > lastUpdates) {
      simulation = (total - lastTotal) / (updates - lastUpdates) / 1000;
    }
    _programInstance = instance;
    _programUpdates = updates;
    _programSimulationTotal = total;

    final measured = (_int(summary?['sampleCount']) ?? 0) > 0;
    final probeTarget = _int(summary?['targetFramesPerSecond']);
    final visualTarget = targetFramesPerSecond();
    return VisualPerformanceSample(
      nativeSurface: true,
      activity: current,
      cores: cores,
      processCpuPercent: cpuPercent,
      pausedCpuPercent: _pausedCpu,
      visualCpuPercent: visualCpu,
      framesPerSecond: fps,
      targetFramesPerSecond:
          _int(metrics?['framesPerSecond']) ??
          (measured && probeTarget != null && probeTarget > 0
              ? probeTarget
              : visualTarget),
      frameAverageMs:
          measured ? _double(summary?['averageFrameMilliseconds']) : null,
      frameP95Ms: measured ? _double(summary?['p95FrameMilliseconds']) : null,
      jankPercent: measured ? _double(summary?['jankPercent']) : null,
      simulationMsPerFrame: simulation,
      thermalState: _int(metrics?['thermalState']),
    );
  }

  VisualPerformanceSample _sampleAndroid(
    int now,
    VisualActivity current,
    double? cpuPercent,
    double? visualCpu,
  ) {
    final stats = source.androidStats;
    final last = _androidStats;
    final lastWall = _androidWall;
    double? fps;
    double? cpu;
    double? simulation;
    if (stats != null &&
        last != null &&
        lastWall != null &&
        stats.sessionId == last.sessionId) {
      final frames = stats.frames - last.frames;
      final seconds = (now - lastWall) / Duration.microsecondsPerSecond;
      if (seconds > 0.2 && frames >= 0) fps = frames / seconds;
      if (frames > 0) {
        final used = stats.cpuMicros;
        final lastUsed = last.cpuMicros;
        if (used != null && lastUsed != null && used >= lastUsed) {
          cpu = (used - lastUsed) / frames / 1000;
        }
        final simulated = stats.simulationMicros - last.simulationMicros;
        if (simulated > 0) simulation = simulated / frames / 1000;
      }
    }
    _androidStats = stats;
    _androidWall = now;
    return VisualPerformanceSample(
      nativeSurface: false,
      activity: current,
      cores: cores,
      processCpuPercent: cpuPercent,
      pausedCpuPercent: _pausedCpu,
      visualCpuPercent: visualCpu,
      framesPerSecond: fps,
      targetFramesPerSecond: targetFramesPerSecond(),
      visualCpuMsPerFrame: cpu,
      simulationMsPerFrame: simulation,
    );
  }

  static int? _int(Object? value) => value is num ? value.toInt() : null;

  static double? _double(Object? value) =>
      value is num && value.isFinite ? value.toDouble() : null;
}
