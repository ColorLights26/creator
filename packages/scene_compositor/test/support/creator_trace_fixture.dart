/// Synthetic sample columns for validator tests. Never measurements or catalog
/// certificates. Matches the lossless export layout of energy_probe.py.
Map<String, Object?> syntheticCreatorTrace(Map<String, Object?> row, double start) {
  double n(String key) => row[key] is num ? (row[key] as num).toDouble() : switch (key) {
    'runnerEPercent' => 30, 'runnerSPercent' => 0.4, 'renderThreadPercent' => 10,
    'gpuAppMsPerSecond' => 120, _ => 0,
  };
  final cpuSpan = n('traceSpanS'), gpuSpan = n('gpuSpanS');
  final pid = row['appPid'];
  final e = n('runnerEPercent'), s = n('runnerSPercent');
  final render = n('renderThreadPercent');
  Map<String, Object?> toc(double at) => {
    'number': 1,
    'startDate': DateTime.fromMillisecondsSinceEpoch((at * 1000).round(), isUtc: true).toIso8601String(),
    'appPids': [pid],
  };
  final gpuNs = (gpuSpan * 1e9).round();
  return {
    'schemaVersion': 1,
    'cpu': {
      'process': 'Runner', 'appPid': pid, 'toc': toc(start),
      'windowStartEpochS': start,
      'sourceSha256': 'synthetic-test-data',
      'samples': [
        [0, ((e - render) * cpuSpan * 1e7).round(), pid, 'Runner', 'E', 'DartWorker'],
        [(cpuSpan * 5e8).round(), (render * cpuSpan * 1e7).round(), pid, 'Runner', 'E', 'Runner'],
        [(cpuSpan * 1e9).round(), (s * cpuSpan * 1e7).round(), pid, 'Runner', 'S', 'Main Thread'],
      ],
    },
    'gpu': {
      'process': 'Runner', 'appPid': pid, 'toc': toc(start + cpuSpan),
      'windowStartEpochS': start + cpuSpan,
      'sourceSha256': 'synthetic-test-data',
      'intervals': [
        [0, (n('gpuAppMsPerSecond') * gpuSpan * 1e6).round(), pid, 'Runner'],
        [gpuNs - 1, 1, 33, 'OtherProcess'],
      ],
    },
  };
}
