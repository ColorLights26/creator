/// One `[ENERGY_PROBE]` record per poll, with the key names of the main
/// app's `energy_probe_record.dart` so the same host driver reads both.
/// Pure Dart: raw platform maps in, a JSON-encodable map out.
library;

/// Prefix of the one-line JSON record the host driver parses.
const energyProbeLogPrefix = '[ENERGY_PROBE]';

/// `ProcessInfo.ThermalState` raw values, in order.
const energyProbeThermalNames = ['nominal', 'fair', 'serious', 'critical'];

/// Studio has no energy governor: the native runtime of Creator exposes no
/// `energyLevel`, so every record reports the best level and says why.
const energyProbeEnergyLevel = 'best';
const energyProbeEnergyGovernor = 'none';

/// The name of a thermal state given as its iOS raw value or its name.
String? energyProbeThermalName(Object? raw) {
  if (raw is String) {
    return energyProbeThermalNames.contains(raw) ? raw : null;
  }
  if (raw is num) {
    final index = raw.toInt();
    return index >= 0 && index < energyProbeThermalNames.length
        ? energyProbeThermalNames[index]
        : null;
  }
  return null;
}

/// The counters of the native surface of one visual, read from the raw
/// `activeSurfaceForScene` payload. Only a payload for [sceneId] counts.
class EnergyProbeSurfaceSnapshot {
  const EnergyProbeSurfaceSnapshot({
    required this.sceneId,
    required this.sessionId,
    this.rendererRevision,
    this.publishedFrameCount,
    this.sampleTimeSeconds,
    this.generation,
    this.backendClass,
    this.gpuCompletedFrameCount,
    this.gpuTotalTimeMs,
    this.gpuLastFrameTimeMs,
    this.gpuSampleTimeSeconds,
    this.gpuTimingSource,
    this.preparing = false,
    this.playing,
    this.programThermalState,
    this.programLowPowerMode,
    this.programFramesPerSecond,
  });

  static EnergyProbeSurfaceSnapshot? parse(
    Map<Object?, Object?>? raw,
    String? sceneId,
  ) {
    if (raw == null || sceneId == null || raw['sceneId'] != sceneId) {
      return null;
    }
    final sessionId = raw['sessionId'];
    if (sessionId is! String) return null;
    final programs = raw['creatorPrograms'];
    final metrics =
        programs is List
            ? programs.whereType<Map<Object?, Object?>>().firstOrNull
            : null;
    return EnergyProbeSurfaceSnapshot(
      sceneId: sceneId,
      sessionId: sessionId,
      rendererRevision: raw['rendererRevision'],
      publishedFrameCount: _int(raw['publishedFrameCount']),
      sampleTimeSeconds: _double(raw['sampleTimeSeconds']),
      generation: _int(raw['generation']),
      backendClass: _string(raw['backendClass']),
      gpuCompletedFrameCount: _int(raw['gpuCompletedFrameCount']),
      gpuTotalTimeMs: _double(raw['gpuTotalTimeMs']),
      gpuLastFrameTimeMs: _double(raw['gpuLastFrameTimeMs']),
      gpuSampleTimeSeconds: _double(raw['gpuSampleTimeSeconds']),
      gpuTimingSource: _string(raw['gpuTimingSource']),
      preparing: raw['preparing'] == true,
      playing: raw['playing'] is bool ? raw['playing'] as bool : null,
      programThermalState: _int(metrics?['thermalState']),
      programLowPowerMode:
          metrics?['lowPowerMode'] is bool
              ? metrics!['lowPowerMode'] as bool
              : null,
      programFramesPerSecond: _int(metrics?['framesPerSecond']),
    );
  }

  final String sceneId;
  final String sessionId;
  final Object? rendererRevision;
  final int? publishedFrameCount;
  final double? sampleTimeSeconds;
  final int? generation;
  final String? backendClass;
  final int? gpuCompletedFrameCount;
  final double? gpuTotalTimeMs;
  final double? gpuLastFrameTimeMs;
  final double? gpuSampleTimeSeconds;
  final String? gpuTimingSource;
  final bool preparing;
  final bool? playing;

  /// From `creatorPrograms[0]` of a native visual; shader visuals report none.
  final int? programThermalState;
  final bool? programLowPowerMode;
  final int? programFramesPerSecond;
}

/// Published frames per second between two polls of the same session and
/// generation (`scenePublishedFramesPerSecond` of the main app). Null, never
/// zero, for the first poll, a session change or an implausible window.
double? energyProbePublishedFps(
  EnergyProbeSurfaceSnapshot? previous,
  EnergyProbeSurfaceSnapshot? current,
) {
  if (previous == null ||
      current == null ||
      previous.sceneId != current.sceneId ||
      previous.sessionId != current.sessionId ||
      previous.rendererRevision != current.rendererRevision ||
      previous.generation == null ||
      previous.generation != current.generation) {
    return null;
  }
  final before = previous.publishedFrameCount;
  final after = current.publishedFrameCount;
  final start = previous.sampleTimeSeconds;
  final end = current.sampleTimeSeconds;
  if (before == null || after == null || start == null || end == null) {
    return null;
  }
  final elapsed = end - start;
  if (!elapsed.isFinite || elapsed < 0.25 || elapsed > 5 || after < before) {
    return null;
  }
  return (after - before) / elapsed;
}

/// Completed GPU work between two polls, weighted by frames
/// (`sceneGpuSample` of the main app). `durationSeconds` is the span between
/// the two `sampleTimeSeconds`; the GPU sample time only validates the window.
({double milliseconds, int frames, double durationSeconds})?
energyProbeGpuSample(
  EnergyProbeSurfaceSnapshot? previous,
  EnergyProbeSurfaceSnapshot? current,
) {
  if (previous == null ||
      current == null ||
      previous.sceneId != current.sceneId ||
      previous.sessionId != current.sessionId ||
      previous.rendererRevision != current.rendererRevision ||
      previous.generation == null ||
      previous.generation != current.generation ||
      previous.backendClass != current.backendClass ||
      current.gpuTimingSource == null ||
      previous.gpuTimingSource != current.gpuTimingSource) {
    return null;
  }
  final start = previous.sampleTimeSeconds;
  final end = current.sampleTimeSeconds;
  final last = current.gpuSampleTimeSeconds;
  final countBefore = previous.gpuCompletedFrameCount;
  final countAfter = current.gpuCompletedFrameCount;
  final totalBefore = previous.gpuTotalTimeMs;
  final totalAfter = current.gpuTotalTimeMs;
  if (start == null ||
      end == null ||
      last == null ||
      countBefore == null ||
      countAfter == null ||
      totalBefore == null ||
      totalAfter == null ||
      !start.isFinite ||
      !end.isFinite ||
      !last.isFinite ||
      !totalBefore.isFinite ||
      !totalAfter.isFinite ||
      end - start < 0.25 ||
      end - start > 5 ||
      last < start ||
      last > end + 0.05 ||
      countBefore < 0 ||
      countAfter <= countBefore ||
      totalBefore < 0 ||
      totalAfter < totalBefore) {
    return null;
  }
  final frames = countAfter - countBefore;
  final milliseconds = (totalAfter - totalBefore) / frames;
  return milliseconds.isFinite
      ? (
        milliseconds: milliseconds,
        frames: frames,
        durationSeconds: end - start,
      )
      : null;
}

/// Builds the records of one probe run. Every rate is a delta between two
/// polls of the same surface session; the first poll and any identity change
/// give null, never an invented zero.
class EnergyProbeRecorder {
  EnergyProbeRecorder({
    required this.visual,
    required this.sceneId,
    this.creator,
    int startWallMicros = 0,
  }) : _lastWallMicros = startWallMicros;

  /// The exact spec text (`baseline`, `id`, `id@max`, ...).
  final String visual;

  /// `creator_<id>`, or null for the baseline.
  final String? sceneId;

  /// The `creator` identity object, or null for the baseline.
  final Map<String, Object?>? creator;

  bool get baseline => sceneId == null;

  EnergyProbeSurfaceSnapshot? _previous;
  int _lastWallMicros;
  int? _lastCpuMicros;

  /// [wallMicros] and [processCpuMicros] come from the same monotonic start
  /// as the recorder's `startWallMicros`; [device] is the raw host
  /// `deviceSnapshot`, [surface] the raw `activeSurfaceForScene` payload.
  Map<String, Object?> record({
    required int epochMilliseconds,
    required int wallMicros,
    required int? processCpuMicros,
    required int flutterFrames,
    required Map<Object?, Object?>? device,
    required Map<Object?, Object?>? surface,
    required Map<String, Object?> viewport,
    String? error,
  }) {
    final intervalMicros = wallMicros - _lastWallMicros;
    final intervalSeconds = intervalMicros / Duration.microsecondsPerSecond;
    final cpu = _cpuPercent(intervalMicros, processCpuMicros);
    _lastWallMicros = wallMicros;
    _lastCpuMicros = processCpuMicros;

    final current = EnergyProbeSurfaceSnapshot.parse(surface, sceneId);
    final publishedFps = energyProbePublishedFps(_previous, current);
    final gpu = energyProbeGpuSample(_previous, current);
    _previous = current;

    final memory = _double(device?['memoryBytes']);
    final flutterFps =
        intervalSeconds > 0 ? flutterFrames / intervalSeconds : null;
    final preparing = current?.preparing ?? false;
    final displayHz = _int(device?['displayHz']);
    return {
      'visual': visual,
      'sceneId': sceneId,
      'epochMs': epochMilliseconds,
      'intervalS': _round(intervalSeconds, 3),
      'thermal':
          energyProbeThermalName(device?['thermalState']) ??
          energyProbeThermalName(current?.programThermalState),
      'lowPower':
          _bool(device?['lowPowerMode']) ?? current?.programLowPowerMode,
      'charging': _bool(device?['charging']),
      'batteryLevel': _double(device?['batteryLevel']),
      'brightness': _double(device?['brightness']),
      'cpu': _round(cpu, 1),
      'memMb': memory == null ? null : _round(memory / (1024 * 1024), 1),
      'flutterFps': _round(flutterFps, 1),
      'displayHz': displayHz,
      'surface': current != null,
      if (surface?['surfacePx'] is Map) 'surfacePx': surface!['surfacePx'],
      'sessionId': current?.sessionId,
      'generation': current?.generation,
      'backendClass': current?.backendClass,
      'gpuTimingSource': current?.gpuTimingSource,
      'publishedFrames': current?.publishedFrameCount,
      'publishedFps': _round(publishedFps, 2),
      'gpuMsPerFrame': _round(gpu?.milliseconds, 3),
      'gpuFrames': gpu?.frames,
      'gpuMsPerSecond':
          gpu == null
              ? null
              : _round(gpu.milliseconds * gpu.frames / gpu.durationSeconds, 3),
      'energyLevel': energyProbeEnergyLevel,
      'energyGovernor': energyProbeEnergyGovernor,
      'playing': current?.playing,
      'preparing': preparing,
      'videoSources': 0,
      'videosWithFrame': 0,
      'pendingMedia': preparing,
      'probeBaseline': baseline,
      'creator': creator,
      'device':
          device == null
              ? null
              : {
                'model': _string(device['model']),
                'systemName': _string(device['systemName']),
                'systemVersion': _string(device['systemVersion']),
                'isPhysical': _bool(device['isPhysical']),
                'displayHz': displayHz,
              },
      'viewport': viewport,
      if (error != null) 'error': error,
    };
  }

  /// Process CPU as % of one core over the poll window, as
  /// `VisualPerformanceMonitor` measures it; windows shorter than 250 ms or
  /// longer than 5 s are not representative.
  double? _cpuPercent(int wallMicros, int? cpuMicros) {
    final lastCpu = _lastCpuMicros;
    if (cpuMicros == null || lastCpu == null) return null;
    final used = cpuMicros - lastCpu;
    if (wallMicros < 250000 || wallMicros > 5000000 || used < 0) return null;
    return used * 100 / wallMicros;
  }
}

int? _int(Object? value) => value is num ? value.toInt() : null;

double? _double(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : null;

String? _string(Object? value) => value is String ? value : null;

bool? _bool(Object? value) => value is bool ? value : null;

double? _round(double? value, int digits) {
  if (value == null || !value.isFinite) return null;
  return double.parse(value.toStringAsFixed(digits));
}
