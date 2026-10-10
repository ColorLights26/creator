/// Evidence check of one Creator device card: the card is only a pointer, and
/// every number it carries must be reproduced from the artifacts the energy
/// probe (`minibase/tool/energy_probe.py`, creator mode) writes for one
/// measured row: the rows file, the per-target console log with its
/// `[ENERGY_PROBE] {json}` lines and the `-probe.jsonl` snapshot of the same
/// lines with host arrival times. Compact CPU/GPU samples retain the TOC,
/// PID and measured columns before large Instruments traces are removed.
/// Metrics are recomputed from those columns. Anything missing, altered
/// or incoherent fails closed as `pending`.
///
/// Shared by `studio/tool/readiness.dart` (prepare) and the app's approval
/// (`minibase/tool/creator_review_support.dart`): one validator, no copies.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'creator_trace_samples.dart';

/// What ran, as the registry and the catalog know it.
class CreatorCardIdentity {
  const CreatorCardIdentity({
    required this.visualId,
    required this.programHash,
    required this.revision,
    required this.buildHash,
    required this.framesPerSecond,
    required this.reactive,
    required this.native,
    required this.role,
    this.controls,
    this.modifiers,
  });

  final String visualId;
  final String programHash;
  final String revision;
  final String buildHash;
  final int framesPerSecond;
  final bool reactive;
  final bool native;
  final String role;
  final Map<String, Object?>? controls;
  final Map<String, Object?>? modifiers;
}

/// A device the protocol may measure on: the contract reference or an
/// explicit profile (`readiness/device_profiles.json`, keyed by hardware
/// identifier). Other devices need their own sustained, artifact-backed
/// calibration; their measurements never stand in for the reference.
class CreatorMeasurementDevice {
  const CreatorMeasurementDevice({
    required this.identifier,
    required this.operatingSystem,
    required this.surfaceWidth,
    required this.surfaceHeight,
    required this.scope,
    required this.isReference,
  });

  final String identifier;
  final String operatingSystem;
  final int? surfaceWidth;
  final int? surfaceHeight;
  final String scope;
  final bool isReference;
}

class CreatorCardVerdict {
  const CreatorCardVerdict(
    this.status,
    this.detail, {
    this.measured = const {},
    this.device = '',
    this.scope = '',
  });

  /// `within` | `exceeds` | `pending`.
  final String status;
  final String detail;
  final Map<String, double> measured;
  final String device;
  final String scope;
}

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// Parses `[ENERGY_PROBE] {json}` console lines exactly as the producer does
/// (`parse_probe_line`): the first `{` to the last `}` after the prefix.
List<Map<String, Object?>> parseProbeConsoleLines(String text) {
  const prefix = '[ENERGY_PROBE]';
  final records = <Map<String, Object?>>[];
  for (final line in const LineSplitter().convert(text)) {
    final at = line.indexOf(prefix);
    if (at < 0) continue;
    final payload = line.substring(at + prefix.length).trim();
    final start = payload.indexOf('{'), end = payload.lastIndexOf('}');
    if (start < 0 || end <= start) continue;
    final Object? record;
    try {
      record = jsonDecode(payload.substring(start, end + 1));
    } on FormatException {
      continue;
    }
    if (record is Map<String, Object?>) records.add(record);
  }
  return records;
}

/// The producer's snapshot beside the console log:
/// `<stem>[-aN]-console.log` → `<stem>-probe.jsonl`.
String probeSnapshotPathFor(String consoleLogPath) => consoleLogPath
    .replaceFirst(RegExp(r'(-a\d+)?-console\.log$'), '-probe.jsonl');

String _canonical(Object? value) => jsonEncode(_sorted(value));
Object? _sorted(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => '$k').toList()..sort();
    return {for (final k in keys) k: _sorted(value[k])};
  }
  if (value is List) return [for (final v in value) _sorted(v)];
  return value;
}

double? _finite(Object? value) {
  if (value is! num) return null;
  final d = value.toDouble();
  return d.isFinite && d >= 0 ? d : null;
}

double _roundTo(double value, int digits) {
  final f = 1;
  var factor = f.toDouble();
  for (var i = 0; i < digits; i++) {
    factor *= 10;
  }
  return (value * factor).round() / factor;
}

bool _close(double? a, double? b, int digits) =>
    a != null && b != null && (a - b).abs() <= 0.5 / _pow10(digits) + 1e-9;
double _pow10(int digits) {
  var f = 1.0;
  for (var i = 0; i < digits; i++) {
    f *= 10;
  }
  return f;
}

/// Validates [card] against its artifacts, [identity], the contract DATA copy
/// ([contractCopy]: the whole `energy_contract.json`) and the explicit device
/// profiles. [profileLabel] names the card's profile in the verdict.
CreatorCardVerdict validateCreatorDeviceCard({
  required Map<String, Object?> card,
  required CreatorCardIdentity identity,
  required Map<String, Object?>? contractCopy,
  required String profileLabel,
  Map<String, Object?> deviceProfiles = const {},
  bool referenceOnly = false,
}) {
  CreatorCardVerdict pending(String why) =>
      CreatorCardVerdict('pending', '$profileLabel: $why');
  if (contractCopy == null) return pending('sin copia del contrato de energía');
  final values = contractCopy['values'];
  if (values is! Map) return pending('la copia del contrato no trae valores');
  Map<String, Object?> section(String name) {
    final s = values[name];
    return s is Map ? s.cast<String, Object?>() : const {};
  }

  double? number(String s, String key) => _finite(section(s)[key]);
  final cardContract = card['energyContract'];
  if (cardContract is! Map ||
      cardContract['semanticHash'] != contractCopy['semanticHash']) {
    return pending(
      'la ficha se juzgó con otro contrato (${cardContract is Map ? cardContract['revision'] : 'ninguno'}); repite cards import',
    );
  }
  // The row, the log and the probe snapshot it came from, by hash.
  final ref = card['row'];
  if (ref is! Map<String, Object?> || ref['file'] is! String) {
    return pending('sin fila de origen');
  }
  final rowFile = File(ref['file'] as String);
  if (!rowFile.existsSync()) {
    return pending('falta la fila de origen ${rowFile.path}');
  }
  if (sha256Hex(rowFile.readAsBytesSync()) != ref['fileSha256']) {
    return pending(
      'el archivo de filas cambió desde la importación (${rowFile.path})',
    );
  }
  Map<String, Object?>? row;
  for (final line in const LineSplitter().convert(rowFile.readAsStringSync())) {
    if (line.trim().isEmpty) continue;
    final Object? candidate;
    try {
      candidate = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (candidate is Map<String, Object?> &&
        candidate['id'] == ref['id'] &&
        candidate['scheduleIndex'] == ref['scheduleIndex'] &&
        candidate['utc'] == ref['utc']) {
      row = candidate;
      break;
    }
  }
  if (row == null) return pending('la fila no está en ${rowFile.path}');
  final log = card['log'];
  final logPath = log is Map ? log['file'] : null;
  if (logPath is! String || log is! Map || log['sha256'] is! String) {
    return pending('sin log de consola');
  }
  final logFile = File(logPath);
  if (!logFile.existsSync()) return pending('falta el log de consola $logPath');
  if (sha256Hex(logFile.readAsBytesSync()) != log['sha256']) {
    return pending('el log de consola cambió desde la importación');
  }
  if (row['consoleLog'] != logPath) {
    return pending('el log de la ficha no es el de su fila');
  }
  final probe = card['probe'];
  final probePath = probe is Map ? probe['file'] : null;
  if (probePath is! String || probe is! Map || probe['sha256'] is! String) {
    return pending('sin snapshot de la sonda (-probe.jsonl)');
  }
  if (probePath != probeSnapshotPathFor(logPath)) {
    return pending('el snapshot de la sonda no es el del log');
  }
  final probeFile = File(probePath);
  if (!probeFile.existsSync()) {
    return pending('falta el snapshot de la sonda $probePath');
  }
  if (sha256Hex(probeFile.readAsBytesSync()) != probe['sha256']) {
    return pending('el snapshot de la sonda cambió desde la importación');
  }
  if (row['status'] != 'measured' || row['targetKind'] != 'creator') {
    return pending('la fila no es una medición del modo creator');
  }
  // Card numbers are the row's numbers.
  final measured = card['measured'];
  if (measured is! Map) return pending('ficha sin medidas');
  const pairs = {
    'achievedFps': 'achievedFps',
    'gpuAppMsPerSecond': 'gpuAppMsPerSecond',
    'gpuAppMsPerPublishedFrame': 'gpuAppMsPerPublishedFrame',
    'efficiencyCorePercent': 'runnerEPercent',
    'performanceCorePercent': 'runnerSPercent',
    'renderThreadPercent': 'renderThreadPercent',
  };
  final numbers = <String, double>{};
  for (final entry in pairs.entries) {
    final fromCard = _finite(measured[entry.key]),
        fromRow = _finite(row[entry.value]);
    if (fromCard == null || fromRow == null) {
      return pending('medida ausente, no finita o negativa: ${entry.key}');
    }
    if ((fromCard - fromRow).abs() > 1e-9) {
      return pending('la ficha no coincide con su fila en ${entry.key}');
    }
    numbers[entry.key] = fromRow;
  }
  // Identity of what ran: program, revision, build and cadence.
  final creator = row['creator'];
  if (creator is! Map) {
    return pending('la sonda no registró la identidad del visual');
  }
  if ('${creator['visualId']}' != identity.visualId) {
    return pending('la sonda midió otro visual (${creator['visualId']})');
  }
  if (creator['programHash'] != identity.programHash) {
    return pending('la sonda midió otro programa (${creator['programHash']})');
  }
  if (creator['revision'] != identity.revision) {
    return pending('la sonda midió otra revisión del visual');
  }
  if (creator['role'] != identity.role ||
      (row['role'] != null && row['role'] != identity.role)) {
    return pending('la sonda midió otro rol del visual');
  }
  final rowBuild = creator['buildHash'];
  if (rowBuild is! String || rowBuild.isEmpty) {
    return pending('la sonda no registró el manifiesto de build');
  }
  if (rowBuild != identity.buildHash) {
    return pending('la sonda corrió otro motor (manifiesto $rowBuild)');
  }
  final nominal = (creator['framesPerSecond'] as num?)?.toInt();
  if (nominal == null || nominal != identity.framesPerSecond) {
    return pending(
      'la sonda corrió a ${nominal ?? '?'} fps, no a ${identity.framesPerSecond}',
    );
  }
  if (creator['signal'] != 'synthetic_loud' && identity.reactive) {
    return pending('sin señal sintética fuerte (${creator['signal']})');
  }
  final measuredProfile = creator['profile'];
  if (measuredProfile is Map && measuredProfile['name'] == 'default') {
    if (identity.controls != null &&
            _canonical(measuredProfile['controls']) !=
                _canonical(identity.controls) ||
        identity.modifiers != null &&
            _canonical(measuredProfile['modifiers']) !=
                _canonical(identity.modifiers)) {
      return pending(
        'la sonda no midió los controles y modificadores iniciales del programa',
      );
    }
  }
  final device = row['device'];
  if (device is! Map || device['isPhysical'] != true) {
    return pending('no se midió en un dispositivo físico');
  }
  // The console log: the same identity, device and viewport on its lines.
  final logRecords = parseProbeConsoleLines(logFile.readAsStringSync());
  if (logRecords.isEmpty) {
    return pending('el log de consola no trae líneas [ENERGY_PROBE]');
  }
  final rowProfile = creator['profile'];
  final profileKey =
      rowProfile is Map
          ? '${rowProfile['name']}|${rowProfile['variation']}'
          : '|';
  var loggedIdentity = 0, loggedSurface = 0;
  for (final record in logRecords) {
    final c = record['creator'];
    if (c is Map) {
      loggedIdentity++;
      final p = c['profile'];
      final key = p is Map ? '${p['name']}|${p['variation']}' : '|';
      if ('${c['visualId']}' != identity.visualId ||
          c['programHash'] != identity.programHash ||
          c['revision'] != identity.revision ||
          c['buildHash'] != identity.buildHash ||
          c['role'] != identity.role ||
          (c['framesPerSecond'] as num?)?.toInt() != nominal ||
          key != profileKey ||
          _canonical(p) != _canonical(rowProfile)) {
        return pending(
          'el log de consola describe otro visual, build o perfil',
        );
      }
    }
    final d = record['device'];
    if (d is Map &&
        ('${d['model']}' != '${device['model']}' ||
            '${d['systemVersion']}' != '${device['systemVersion']}' ||
            d['isPhysical'] != true)) {
      return pending('el log de consola describe otro dispositivo');
    }
    if (record['surface'] == true) loggedSurface++;
  }
  if (loggedIdentity == 0) {
    return pending('el log de consola no identifica el visual medido');
  }
  // The probe snapshot: the same lines with host time, and a contiguous
  // window of exactly the row's samples that reproduces its summary.
  final snapshot = <Map<String, Object?>>[];
  for (final line in const LineSplitter().convert(
    probeFile.readAsStringSync(),
  )) {
    if (line.trim().isEmpty) continue;
    final Object? record;
    try {
      record = jsonDecode(line);
    } on FormatException {
      return pending('snapshot de la sonda ilegible');
    }
    if (record is! Map<String, Object?> ||
        _finite(record['hostTime']) == null) {
      return pending('snapshot de la sonda sin hora de llegada');
    }
    snapshot.add(record);
  }
  if (snapshot.isEmpty) return pending('snapshot de la sonda vacío');
  final logged = {
    for (final r in logRecords) '${r['epochMs']}|${r['visual']}': _canonical(r),
  };
  for (final record in snapshot) {
    final copy = Map<String, Object?>.from(record)..remove('hostTime');
    if (logged['${record['epochMs']}|${record['visual']}'] !=
        _canonical(copy)) {
      return pending(
        'el snapshot de la sonda no coincide con el log de consola',
      );
    }
  }
  snapshot.sort(
    (a, b) => (a['hostTime'] as num).compareTo(b['hostTime'] as num),
  );
  final samples = (row['probeSamples'] as num?)?.toInt();
  if (samples == null || samples <= 0 || samples > snapshot.length) {
    return pending(
      'la fila declara $samples muestras y el snapshot trae ${snapshot.length}',
    );
  }
  final warmup = _finite(row['warmupS']);
  final needWarmup = number('protocol', 'measurementWarmupSeconds'),
      needCpu = number('protocol', 'measurementCpuWindowSecondsMinimum'),
      needGpu = number('protocol', 'measurementGpuWindowSeconds');
  if (needWarmup == null || needCpu == null || needGpu == null) {
    return pending('la copia del contrato no trae el protocolo de medición');
  }
  if (warmup == null || warmup < needWarmup) {
    return pending(
      'warmup ${warmup?.toStringAsFixed(0) ?? '?'} s < ${needWarmup.toStringAsFixed(0)} s del contrato',
    );
  }
  final attached = snapshot.firstWhere(
    (r) => r['surface'] == true && r['preparing'] != true,
    orElse: () => const {},
  );
  if (attached.isEmpty) {
    return pending(
      identity.native
          ? 'la sonda nunca vio la superficie nativa'
          : 'sin superficie nativa: la ruta legacy necesita cadencia medida y GPU del trace Metal; sin datos queda pendiente',
    );
  }
  final attachedAt = (attached['hostTime'] as num).toDouble();
  List<Map<String, Object?>>? window;
  (int, int)? surface;
  for (var start = 0; start + samples <= snapshot.length; start++) {
    final slice = snapshot.sublist(start, start + samples);
    final fps = <double>[], mem = <double>[];
    final thermal = <String>{};
    final energy = <String, int>{};
    var surfaces = 0, pendingMedia = 0, lowPower = false, charging = false;
    (int, int)? px;
    var pxConsistent = true;
    for (final r in slice) {
      if (r['publishedFps'] is num)
        fps.add((r['publishedFps'] as num).toDouble());
      if (r['memMb'] is num) mem.add((r['memMb'] as num).toDouble());
      if (r['thermal'] is String && (r['thermal'] as String).isNotEmpty) {
        thermal.add(r['thermal'] as String);
      }
      if (r['energyLevel'] != null) {
        energy['${r['energyLevel']}'] =
            (energy['${r['energyLevel']}'] ?? 0) + 1;
      }
      if (r['surface'] == true) surfaces++;
      if (r['pendingMedia'] == true) pendingMedia++;
      lowPower |= r['lowPower'] == true;
      charging |= r['charging'] == true;
      final s = r['surfacePx'];
      if (s is Map && s['width'] is num && s['height'] is num) {
        final here = (
          (s['width'] as num).toInt(),
          (s['height'] as num).toInt(),
        );
        if (px != null && px != here) pxConsistent = false;
        px = here;
      } else if (r['surface'] == true) {
        pxConsistent = false;
      }
    }
    double? mean(List<double> v, int digits) =>
        v.isEmpty
            ? null
            : _roundTo(v.reduce((a, b) => a + b) / v.length, digits);
    String? mode() {
      String? best;
      var count = -1;
      for (final e in energy.entries) {
        if (e.value > count) {
          best = e.key;
          count = e.value;
        }
      }
      return best;
    }

    final rowThermal = row['thermalStates'];
    final rowThermalSet =
        rowThermal is List ? rowThermal.map((s) => '$s').toSet() : null;
    final reproduces =
        _close(mean(fps, 2), _finite(row['achievedFps']), 2) &&
        _close(mean(mem, 1), _finite(row['memMb']), 1) &&
        rowThermalSet != null &&
        rowThermalSet.length == thermal.length &&
        rowThermalSet.containsAll(thermal) &&
        '${row['energyLevel']}' == '${mode()}' &&
        (row['lowPower'] == true) == lowPower &&
        (row['charging'] == true) == charging &&
        (row['surfaceSamples'] as num?)?.toInt() == surfaces &&
        ((row['pendingMediaSamples'] as num?)?.toInt() ?? 0) == pendingMedia &&
        (slice.first['hostTime'] as num).toDouble() >=
            attachedAt + warmup - 1.0;
    if (reproduces) {
      window = slice;
      surface = pxConsistent ? px : null;
      break;
    }
  }
  if (window == null) {
    return pending(
      'las muestras de la sonda no reproducen la fila (cadencia, memoria, térmico, energía o superficie)',
    );
  }
  if (window.any((r) => r['playing'] != true)) {
    return pending('la ventana incluye reproducción pausada o desconocida');
  }
  if (loggedSurface < (row['surfaceSamples'] as num? ?? 0)) {
    return pending(
      'el log de consola trae menos muestras con superficie que la fila',
    );
  }
  // The compact export retains sample columns, not precomputed percentages.
  // Recompute the CPU split and union of the app's GPU intervals on every use.
  final traceRef = card['traceEvidence'];
  final rowTrace = row['traceEvidence'];
  if (traceRef is! Map ||
      rowTrace is! Map ||
      traceRef['file'] is! String ||
      traceRef['sha256'] is! String ||
      _canonical(traceRef) != _canonical(rowTrace)) {
    return pending('sin muestras originales del trace CPU/GPU');
  }
  final traceFile = File(traceRef['file'] as String);
  if (!traceFile.existsSync() || traceFile.lengthSync() > 64 * 1024 * 1024) {
    return pending('faltan muestras del trace o el archivo supera 64 MiB');
  }
  final traceBytes = traceFile.readAsBytesSync();
  if (sha256Hex(traceBytes) != traceRef['sha256']) {
    return pending('las muestras del trace cambiaron desde la importación');
  }
  final CreatorTraceMetrics trace;
  try {
    trace = CreatorTraceMetrics.parse(
      jsonDecode(utf8.decode(traceBytes)),
      row['appPid'],
    );
  } on FormatException catch (error) {
    return pending('muestras del trace inválidas: ${error.message}');
  }
  for (final metric in trace.values.entries) {
    final digits = metric.key.endsWith('SpanS') ? 3 : 2;
    if (!_close(metric.value, _finite(row[metric.key]), digits)) {
      return pending('el trace no reproduce la fila en ${metric.key}');
    }
  }
  final cpuWindow = trace.values['traceSpanS']!,
      gpuWindow = trace.values['gpuSpanS']!;
  if (cpuWindow < needCpu) {
    return pending(
      'ventana de CPU ${cpuWindow.toStringAsFixed(1)} s < ${needCpu.toStringAsFixed(0)} s del contrato',
    );
  }
  if (gpuWindow < needGpu) {
    return pending(
      'ventana de GPU ${gpuWindow.toStringAsFixed(1)} s < ${needGpu.toStringAsFixed(0)} s del contrato',
    );
  }
  if (row['windowSource'] != 'toc')
    return pending('la ventana no viene del TOC del trace');
  final windowStart = _finite(row['probeWindowStartEpochS']);
  final windowEnd = _finite(row['probeWindowEndEpochS']);
  if (windowStart == null ||
      windowEnd == null ||
      (windowStart - trace.start).abs() > 0.01 ||
      (windowEnd - trace.end).abs() > 0.01 ||
      window!.any(
        (r) =>
            (r['hostTime'] as num) < trace.start - 1 ||
            (r['hostTime'] as num) > trace.end + 1,
      )) {
    return pending('la ventana de la sonda no coincide con los traces');
  }
  final appPid = int.tryParse('${row['appPid']}');
  final runnerPids = row['runnerPids'];
  if (appPid == null ||
      runnerPids is! List ||
      !runnerPids.any((p) => '$p' == '$appPid')) {
    return pending('el trace de CPU no vincula el pid de la app');
  }
  final warnings = row['warnings'];
  if (warnings is! List) return pending('fila sin lista de avisos');
  const fatal = [
    'no gpu samples',
    'no native surface',
    'native surface missing',
    'Runner not in trace',
    'no cpu trace',
    'no gpu trace',
    'no frames published',
    'no probe lines',
    'short probe window',
    'pending media',
    'console arrival jitter',
    'several Runner pids',
    'other Runner pids',
    'not in trace TOC',
    'window from command start',
    'toc unreadable',
    'toc export exit',
    'time profile unavailable',
    'gpu intervals unavailable',
    'gpu export exit',
    'xctrace exit',
    'trace span',
    'gpu span',
    'thermal ',
    'energy level',
    'low power',
  ];
  for (final warning in warnings) {
    if (fatal.any((f) => '$warning'.contains(f))) {
      return pending('la fila avisa: $warning');
    }
  }
  // Thermal state and governor during the whole run.
  final states = row['thermalStates'];
  if (row['startThermal'] != 'nominal' ||
      states is! List ||
      states.isEmpty ||
      states.any((s) => s != 'nominal')) {
    return pending(
      'estado térmico no nominal durante la medición (${row['startThermal']}, $states)',
    );
  }
  if (row['energyLevel'] != 'best') {
    return pending('nivel de energía ${row['energyLevel']} ≠ best');
  }
  if (row['lowPower'] == true) return pending('modo de bajo consumo activo');
  // GPU per published frame is derived from GPU/s and cadence.
  final fps = numbers['achievedFps']!;
  final gpuFrame = numbers['gpuAppMsPerPublishedFrame']!;
  if (fps < nominal * 0.9) {
    return pending(
      'alcanza ${fps.toStringAsFixed(1)} fps de $nominal nominales',
    );
  }
  if ((gpuFrame - _roundTo(numbers['gpuAppMsPerSecond']! / fps, 3)).abs() >
      0.002) {
    return pending('GPU por cuadro incoherente con GPU/s y cadencia');
  }
  if (fps < nominal * 0.9) {
    return pending(
      'alcanza ${fps.toStringAsFixed(1)} fps de $nominal nominales',
    );
  }
  final cpuFrame = numbers['renderThreadPercent']! / 100 * 1000 / nominal;
  if (gpuFrame + cpuFrame > 1000 / nominal) {
    return pending(
      '${gpuFrame.toStringAsFixed(1)} ms de GPU + ${cpuFrame.toStringAsFixed(1)} ms de CPU por cuadro no caben en ${(1000 / nominal).toStringAsFixed(1)} ms (${section('creatorProgram')['feasibilityRule']})',
    );
  }
  // The device, explicit: the reference or a registered profile.
  final reference = section('reference');
  final model = '${device['model']}';
  final CreatorMeasurementDevice target;
  if (model == '${reference['identifier']}') {
    target = CreatorMeasurementDevice(
      identifier: model,
      operatingSystem: '${reference['operatingSystem'] ?? ''}',
      surfaceWidth: (reference['surfaceWidth'] as num?)?.toInt(),
      surfaceHeight: (reference['surfaceHeight'] as num?)?.toInt(),
      scope: 'referencia',
      isReference: true,
    );
  } else {
    final profile = deviceProfiles[model];
    if (profile is! Map) {
      return pending(
        'dispositivo $model ≠ referencia ${reference['identifier']} y sin perfil registrado',
      );
    }
    if (profile['systemVersion'] != null &&
        profile['systemVersion'] != device['systemVersion']) {
      return pending('otra versión de sistema para el perfil $model');
    }
    target = CreatorMeasurementDevice(
      identifier: model,
      operatingSystem: '${profile['operatingSystem'] ?? ''}',
      surfaceWidth: (profile['surfaceWidth'] as num?)?.toInt(),
      surfaceHeight: (profile['surfaceHeight'] as num?)?.toInt(),
      scope: '${profile['scope'] ?? model}',
      isReference: false,
    );
  }
  final osMajor = RegExp(
    r'\d+',
  ).firstMatch('${device['systemVersion']}')?.group(0);
  final wantMajor = RegExp(r'\d+').firstMatch(target.operatingSystem)?.group(0);
  if (osMajor == null || wantMajor == null || osMajor != wantMajor) {
    return pending(
      'sistema ${device['systemVersion']} ≠ ${target.operatingSystem} de ${target.identifier}',
    );
  }
  // The surface the device drew, as the probe measured it (never inferred).
  if (surface == null) {
    return pending(
      'sin superficie medida en la sonda (surfacePx); no se infiere del viewport',
    );
  }
  if (target.surfaceWidth == null ||
      target.surfaceHeight == null ||
      surface.$1 != target.surfaceWidth ||
      surface.$2 != target.surfaceHeight) {
    return pending(
      'superficie ${surface.$1}×${surface.$2} ≠ ${target.surfaceWidth}×${target.surfaceHeight} de ${target.identifier}',
    );
  }
  if (!target.isReference) {
    if (!referenceOnly) {
      final profile = deviceProfiles[model] as Map;
      final calibrated = _calibratedDeviceVerdict(
        profile: profile,
        identity: identity,
        contractCopy: contractCopy,
        label: profileLabel,
        numbers: numbers,
        device: target,
        charging: row['charging'] == true,
        brightness: window.map((r) => _finite(r['brightness'])).toList(),
      );
      if (calibrated != null) return calibrated;
    }
    return CreatorCardVerdict(
      'pending',
      '$profileLabel: evidencia respaldada en ${target.identifier} (alcance ${target.scope}); el contrato no trae techo para ese dispositivo y no equivale a la referencia',
      measured: numbers,
      device: target.identifier,
      scope: target.scope,
    );
  }
  // Against the slot ceilings of the contract copy.
  final slot = section('slotCeilings')[identity.role];
  final ceilGpu =
      slot is Map ? (slot['gpuMsPerSecond'] as num?)?.toDouble() : null;
  final ceilE =
      slot is Map ? (slot['efficiencyCorePercent'] as num?)?.toDouble() : null;
  if (ceilGpu == null || ceilE == null) {
    return pending('el contrato no trae techo para el slot ${identity.role}');
  }
  final gpuMargin = number('comparison', 'gpuMarginPercent') ?? 0;
  final eMargin = number('comparison', 'efficiencyCoreMarginPercent') ?? 0;
  final bound = number('comparison', 'performanceCorePercentOfCoreBound');
  final over = <String>[];
  final gpu = numbers['gpuAppMsPerSecond']!,
      e = numbers['efficiencyCorePercent']!,
      sCore = numbers['performanceCorePercent']!;
  if (gpu > ceilGpu * (1 + gpuMargin / 100)) {
    over.add('GPU ${gpu.toStringAsFixed(1)} ms/s > techo $ceilGpu');
  }
  if (e > ceilE * (1 + eMargin / 100)) {
    over.add('CPU E ${e.toStringAsFixed(1)}% > techo $ceilE');
  }
  if (bound != null && sCore > bound) {
    over.add('CPU S ${sCore.toStringAsFixed(1)}% > $bound');
  }
  return CreatorCardVerdict(
    over.isEmpty ? 'within' : 'exceeds',
    over.isEmpty
        ? '$profileLabel: dentro del techo de su slot (${identity.role}) a ${fps.toStringAsFixed(1)} fps'
        : '$profileLabel: ${over.join('; ')}',
    measured: numbers,
    device: target.identifier,
    scope: target.scope,
  );
}

/// A device envelope is the load of an actual visual that stayed nominal for
/// the contract's sustained duration. Both CPU and GPU must be dominated by
/// one anchor at the same cadence; maxima from different workloads cannot be
/// combined. The isolated renderer uses the same surface for both roles: each
/// anchor retains its own actual role, while its measured CPU/GPU load bounds
/// either isolated role. This never certifies a composition. No iPhone
/// ceilings or hand-entered percentages are used for another device.
CreatorCardVerdict? _calibratedDeviceVerdict({
  required Map profile,
  required CreatorCardIdentity identity,
  required Map<String, Object?> contractCopy,
  required String label,
  required Map<String, double> numbers,
  required CreatorMeasurementDevice device,
  required bool charging,
  required List<double?> brightness,
}) {
  final anchors = profile['calibrationAnchors'];
  if (anchors is! List || anchors.isEmpty) return null;
  final errors = <String>[];
  var valid = 0;
  for (final anchor in anchors) {
    if (anchor is! Map ||
        anchor['identity'] is! Map ||
        anchor['card'] is! Map) {
      errors.add('ancla incompleta');
      continue;
    }
    final a = anchor['identity'] as Map;
    if (a['buildHash'] != identity.buildHash) {
      continue;
    }
    final fps = a['framesPerSecond'];
    if (fps is! int ||
        fps != identity.framesPerSecond ||
        !['background', 'overlay'].contains(a['role']) ||
        fps <= 0 ||
        fps > 60 ||
        [
          'visualId',
          'programHash',
          'revision',
        ].any((key) => a[key] is! String || (a[key] as String).isEmpty)) {
      errors.add('identidad del ancla incompleta');
      continue;
    }
    final anchorCard = (anchor['card'] as Map).cast<String, Object?>();
    // Removing the calibration makes recursion impossible. This validation
    // returns backed numbers only after all raw card checks have passed.
    final uncalibrated = Map<String, Object?>.from(profile)
      ..remove('calibrationAnchors');
    final checked = validateCreatorDeviceCard(
      card: anchorCard,
      identity: CreatorCardIdentity(
        visualId: a['visualId'] as String,
        programHash: a['programHash'] as String,
        revision: a['revision'] as String,
        buildHash: identity.buildHash,
        framesPerSecond: fps,
        reactive: a['reactive'] == true,
        native: a['native'] == true,
        role: a['role'] as String,
        controls:
            a['controls'] is Map
                ? (a['controls'] as Map).cast<String, Object?>()
                : null,
        modifiers:
            a['modifiers'] is Map
                ? (a['modifiers'] as Map).cast<String, Object?>()
                : null,
      ),
      contractCopy: contractCopy,
      profileLabel: 'ancla',
      deviceProfiles: {device.identifier: uncalibrated},
    );
    if (checked.measured.isEmpty || checked.device != device.identifier) {
      errors.add(checked.detail);
      continue;
    }
    final floor =
        anchor['soak'] is Map
            ? _finite((anchor['soak'] as Map)['minimumBrightness'])
            : null;
    if (floor == null ||
        floor > 1 ||
        brightness.isEmpty ||
        brightness.any((b) => b == null || b > floor)) {
      errors.add('sin cobertura del brillo medido');
      continue;
    }
    final error = _validateDeviceSoak(
      anchor,
      anchorCard,
      contractCopy,
      device,
      charging,
      floor,
    );
    if (error != null) {
      errors.add(error);
      continue;
    }
    valid++;
    final cpu =
        numbers['efficiencyCorePercent']! + numbers['performanceCorePercent']!;
    final anchorCpu =
        checked.measured['efficiencyCorePercent']! +
        checked.measured['performanceCorePercent']!;
    if (cpu <= anchorCpu &&
        numbers['gpuAppMsPerSecond']! <=
            checked.measured['gpuAppMsPerSecond']!) {
      return CreatorCardVerdict(
        'within',
        '$label: carga dentro del ancla ${a['visualId']} con prueba sostenida; alcance ${device.scope}, ${charging ? 'conectado' : 'batería'}, visual aislado',
        measured: numbers,
        device: device.identifier,
        scope:
            '${device.scope}, ${charging ? 'conectado' : 'batería'}, brillo ≤ ${(floor * 100).toStringAsFixed(0)}%, visual aislado',
      );
    }
  }
  return CreatorCardVerdict(
    'pending',
    '$label: ${valid > 0 ? 'la carga requiere otra ancla sostenida' : 'sin ancla sostenida válida${errors.isEmpty ? '' : ': ${errors.join('; ')}'}'}; alcance ${device.scope}',
    measured: numbers,
    device: device.identifier,
    scope: device.scope,
  );
}

String? _validateDeviceSoak(
  Map anchor,
  Map<String, Object?> card,
  Map<String, Object?> contract,
  CreatorMeasurementDevice device,
  bool charging,
  double minimumBrightness,
) {
  final soak = anchor['soak'];
  if (soak is! Map) return 'ancla sin prueba sostenida';
  String? artifact(Object? ref) {
    if (ref is! Map || ref['file'] is! String || ref['sha256'] is! String)
      return null;
    final file = File(ref['file'] as String);
    if (!file.existsSync() || file.lengthSync() > 16 * 1024 * 1024) return null;
    final bytes = file.readAsBytesSync();
    return sha256Hex(bytes) == ref['sha256']
        ? utf8.decode(bytes, allowMalformed: true)
        : null;
  }

  final console = artifact(soak['console']), snapshot = artifact(soak['probe']);
  if (console == null || snapshot == null)
    return 'artefactos de la prueba sostenida ausentes o alterados';
  final logged = {
    for (final r in parseProbeConsoleLines(console))
      '${r['epochMs']}|${r['visual']}': _canonical(r),
  };
  final rowRef = card['row'] as Map;
  final rows = File(rowRef['file'] as String).readAsLinesSync();
  Map? row;
  for (final line in rows) {
    try {
      final r = jsonDecode(line);
      if (r is Map &&
          r['id'] == rowRef['id'] &&
          r['scheduleIndex'] == rowRef['scheduleIndex'] &&
          r['utc'] == rowRef['utc']) {
        row = r;
        break;
      }
    } on FormatException {
      continue;
    }
  }
  if (row == null) return 'fila del ancla ausente';
  final creator = row['creator'] as Map;
  final expectedDevice = row['device'];
  if ((row['charging'] == true) != charging)
    return 'alimentación distinta de la del ancla';
  final values = contract['values'] as Map;
  final minutes =
      ((values['reference'] as Map)['certificationSoakMinutes'] as num?)
          ?.toDouble();
  final warmup =
      ((values['protocol'] as Map)['measurementWarmupSeconds'] as num?)
          ?.toDouble();
  if (minutes == null || minutes < 60 || warmup == null)
    return 'sin protocolo sostenido';
  double? attached, first, last, lastEpoch;
  var count = 0;
  try {
    for (final line in const LineSplitter().convert(snapshot)) {
      if (line.trim().isEmpty) continue;
      final record = jsonDecode(line);
      if (record is! Map<String, Object?> ||
          _finite(record['hostTime']) == null ||
          _finite(record['epochMs']) == null)
        return 'muestra sostenida sin reloj';
      final copy = Map<String, Object?>.from(record)..remove('hostTime');
      if (logged['${record['epochMs']}|${record['visual']}'] !=
          _canonical(copy))
        return 'prueba sostenida distinta del log';
      if (_canonical(record['creator']) != _canonical(creator) ||
          _canonical(record['device']) != _canonical(expectedDevice))
        return 'otra identidad o dispositivo en la prueba sostenida';
      if (record['surface'] != true || record['preparing'] == true) continue;
      final time = (record['hostTime'] as num).toDouble();
      attached ??= time;
      if (time < attached + warmup) continue;
      if (record['playing'] != true)
        return 'reproducción pausada o desconocida en la prueba sostenida';
      final epoch = (record['epochMs'] as num).toDouble() / 1000;
      if (last != null &&
          (time <= last ||
              time - last > 6 ||
              epoch <= lastEpoch! ||
              epoch - lastEpoch > 6 ||
              ((time - last) - (epoch - lastEpoch)).abs() > 2))
        return 'hueco o reloj incoherente en la prueba sostenida';
      if (record['thermal'] != 'nominal' ||
          record['energyLevel'] != 'best' ||
          record['lowPower'] == true ||
          (record['charging'] == true) != charging ||
          record['pendingMedia'] == true)
        return 'condición térmica o de alimentación fuera del protocolo sostenido';
      final brightness = _finite(record['brightness']);
      if (brightness == null ||
          brightness > 1 ||
          brightness < minimumBrightness)
        return 'brillo fuera del alcance sostenido';
      final px = record['surfacePx'];
      if (px is! Map ||
          px['width'] != device.surfaceWidth ||
          px['height'] != device.surfaceHeight)
        return 'otra superficie en la prueba sostenida';
      final fps = _finite(record['publishedFps']);
      if (fps == null || fps < (creator['framesPerSecond'] as num) * .9)
        return 'cadencia insuficiente en la prueba sostenida';
      first ??= time;
      last = time;
      lastEpoch = epoch;
      count++;
    }
  } on FormatException {
    return 'prueba sostenida ilegible';
  }
  if (first == null ||
      last == null ||
      last - first < minutes * 60 ||
      count < minutes * 60 / 6)
    return 'prueba sostenida más corta que $minutes minutos';
  return null;
}
