/// Recomputes energy metrics from the compact, lossless sample columns exported
/// by energy_probe.py before it removes the large Instruments trace bundles.
library;

class CreatorTraceMetrics {
  const CreatorTraceMetrics(this.values, this.start, this.end);
  final Map<String, double> values;
  final double start;
  final double end;

  static CreatorTraceMetrics parse(Object? json, Object? expectedPid) {
    Never invalid(String detail) => throw FormatException('trace: $detail');
    Map section(Object? value) {
      if (value is! Map) invalid('sección ausente');
      return value;
    }

    double number(Object? value) {
      if (value is! num || !value.isFinite || value < 0) {
        invalid('muestra no finita o negativa');
      }
      return value.toDouble();
    }

    List rows(Object? value) {
      if (value is! List || value.isEmpty || value.length > 1000000) {
        invalid('sin muestras o exceso de muestras');
      }
      return value;
    }

    int pid(Object? value) {
      final result = int.tryParse('$value');
      if (result == null || result <= 0) invalid('PID inválido');
      return result;
    }

    final root = section(json);
    if (root['schemaVersion'] != 1) invalid('versión desconocida');
    final appPid = pid(expectedPid);
    final cpu = section(root['cpu']), gpu = section(root['gpu']);
    for (final table in [cpu, gpu]) {
      if (pid(table['appPid']) != appPid || table['process'] != 'Runner') {
        invalid('proceso distinto de la app');
      }
      final toc = section(table['toc']);
      final pids = toc['appPids'];
      if (pids is! List ||
          !pids.any((p) => '$p' == '$appPid') ||
          toc['number'] is! int ||
          (toc['number'] as int) < 1 ||
          DateTime.tryParse('${toc['startDate']}') == null) {
        invalid('TOC sin vínculo con el PID de la app');
      }
      final tocTime =
          DateTime.parse('${toc['startDate']}').millisecondsSinceEpoch / 1000;
      if ((number(table['windowStartEpochS']) - tocTime).abs() > 0.01) {
        invalid('inicio distinto del TOC');
      }
    }
    double? first, last;
    var eNs = 0.0, sNs = 0.0, renderNs = 0.0, appSamples = 0;
    for (final item in rows(cpu['samples'])) {
      if (item is! List || item.length != 6)
        invalid('columnas de CPU inválidas');
      final at = number(item[0]), weight = number(item[1]);
      first = first == null || at < first ? at : first;
      last = last == null || at > last ? at : last;
      if ('${item[2]}' != '$appPid' || item[3] != 'Runner') continue;
      appSamples++;
      switch (item[4]) {
        case 'E':
          eNs += weight;
        case 'S':
          sNs += weight;
        default:
          invalid('núcleo desconocido para la app');
      }
      if (item[5] == 'Runner') renderNs += weight;
    }
    final cpuSpan = (last! - first!) / 1e9;
    if (cpuSpan <= 0 || appSamples == 0)
      invalid('CPU sin ventana o muestras de la app');
    final intervals = <(double, double)>[];
    double? gpuFirst, gpuLast;
    for (final item in rows(gpu['intervals'])) {
      if (item is! List || item.length != 4)
        invalid('columnas de GPU inválidas');
      final at = number(item[0]), end = at + number(item[1]);
      gpuFirst = gpuFirst == null || at < gpuFirst ? at : gpuFirst;
      gpuLast = gpuLast == null || end > gpuLast ? end : gpuLast;
      if ('${item[2]}' == '$appPid' && item[3] == 'Runner')
        intervals.add((at, end));
    }
    final gpuSpanNs = gpuLast! - gpuFirst!;
    if (gpuSpanNs <= 0 || intervals.isEmpty)
      invalid('GPU sin ventana o intervalos de la app');
    intervals.sort((a, b) => a.$1.compareTo(b.$1));
    var busyNs = 0.0, begin = intervals.first.$1, end = intervals.first.$2;
    for (final next in intervals.skip(1)) {
      if (next.$1 > end) {
        busyNs += end - begin;
        begin = next.$1;
        end = next.$2;
      } else if (next.$2 > end) {
        end = next.$2;
      }
    }
    busyNs += end - begin;
    final start = number(cpu['windowStartEpochS']) + first / 1e9;
    final cpuEnd = start + cpuSpan;
    final gpuStart = number(gpu['windowStartEpochS']) + gpuFirst / 1e9;
    final cpuToc = section(cpu['toc']), gpuToc = section(gpu['toc']);
    // Instruments can add Time Profiler to Metal System Trace. Both tables
    // then share one run, PID and clock origin. An overlap from independent
    // recordings still fails closed; their clocks cannot be spliced together.
    final sameRun =
        cpuToc['number'] == gpuToc['number'] &&
        cpuToc['startDate'] == gpuToc['startDate'];
    if (gpuStart < cpuEnd - 1 && !sameRun) {
      invalid('ventana GPU anterior al fin de CPU, sin un trace conjunto');
    }
    return CreatorTraceMetrics(
      {
        'traceSpanS': cpuSpan,
        'gpuSpanS': gpuSpanNs / 1e9,
        'runnerEPercent': eNs / 1e6 / cpuSpan / 10,
        'runnerSPercent': sNs / 1e6 / cpuSpan / 10,
        'renderThreadPercent': renderNs / 1e6 / cpuSpan / 10,
        'gpuAppMsPerSecond': 1000 * busyNs / gpuSpanNs,
      },
      start < gpuStart ? start : gpuStart,
      cpuEnd > number(gpu['windowStartEpochS']) + gpuLast / 1e9
          ? cpuEnd
          : number(gpu['windowStartEpochS']) + gpuLast / 1e9,
    );
  }
}
