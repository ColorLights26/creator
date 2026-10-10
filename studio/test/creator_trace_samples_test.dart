import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:scene_compositor/creator_trace_samples.dart';

void main() {
  Map<String, Object?> evidence() {
    final origin = DateTime.parse('2026-10-08T00:00:00Z');
    Map<String, Object?> table(String rows, List<Object?> samples) => {
      'appPid': 42,
      'process': 'Runner',
      'toc': {
        'appPids': ['42'],
        'number': 1,
        'startDate': origin.toIso8601String(),
      },
      'windowStartEpochS': origin.millisecondsSinceEpoch / 1000,
      rows: samples,
    };
    return {
      'schemaVersion': 1,
      'cpu': table('samples', [
        [0, 1000000, '42', 'Runner', 'E', 'Runner'],
        [20000000000, 1000000, '42', 'Runner', 'E', 'Runner'],
      ]),
      'gpu': table('intervals', [
        [0, 2000000000, 42, 'Runner'],
        [18000000000, 2000000000, 42, 'Runner'],
      ]),
    };
  }

  test('joint Instruments tables share a run and reproduce CPU and GPU', () {
    final metrics = CreatorTraceMetrics.parse(evidence(), 42);
    expect(metrics.values['traceSpanS'], 20);
    expect(metrics.values['gpuSpanS'], 20);
    expect(metrics.values['gpuAppMsPerSecond'], 200);
    expect(metrics.values['runnerEPercent'], closeTo(0.01, 0.00001));
    expect(metrics.end - metrics.start, 20);
  });

  test(
    'overlapping independent recordings cannot impersonate a joint trace',
    () {
      final raw = jsonDecode(jsonEncode(evidence())) as Map;
      final gpu = raw['gpu'] as Map;
      final date = DateTime.parse('2026-10-08T00:00:02Z');
      gpu['windowStartEpochS'] = date.millisecondsSinceEpoch / 1000;
      (gpu['toc'] as Map)['startDate'] = date.toIso8601String();
      expect(() => CreatorTraceMetrics.parse(raw, 42), throwsFormatException);
    },
  );

  test('same clock with a different Instruments run is still refused', () {
    final raw = jsonDecode(jsonEncode(evidence())) as Map;
    ((raw['gpu'] as Map)['toc'] as Map)['number'] = 2;
    expect(() => CreatorTraceMetrics.parse(raw, 42), throwsFormatException);
  });
}
