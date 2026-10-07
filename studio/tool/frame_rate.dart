import 'dart:collection';
import 'dart:convert';
import 'dart:io';

/// Cuadros por segundo decididos por energía, reversibles.
///
/// `framesPerSecond` de cada `<id>_metadata.dart` sigue siendo la única fuente
/// que leen Studio y la aprobación de Color Lights. Este comando sólo reescribe
/// esa línea y guarda en `energy/frame_rate_record.json` (fuera de `lib/` y de
/// los assets) el valor del autor, el aplicado y la medición que lo justifica.
const frameRateUsage = '''
Uso (desde studio/):
  dart run tool/frame_rate.dart status
  dart run tool/frame_rate.dart check
  dart run tool/frame_rate.dart record --from-csv <medición.csv> --base-commit <commit medido> [--date AAAA-MM-DD] [--k 28.47]
  dart run tool/frame_rate.dart apply (--ids a,b | --all)
  dart run tool/frame_rate.dart revert (--ids a,b | --all)
Opción común: --catalog <ruta de packages/visual_catalog>.
''';

/// Comentario que deja `apply` en la línea cuando el valor difiere del autor.
const frameRateMarker = '// energía: ver energy/frame_rate_record.json';

const frameRateReason =
    'R5: no cabe en el presupuesto de 60 fps (GPU <= 4 ms, CPU <= 2 ms); '
    'si cabe en el de 30';

const frameRatePolicy =
    'framesPerSecond de cada <id>_metadata.dart sigue siendo la única fuente '
    'que leen Studio y la aprobación. Aquí se registra, por visual, el valor '
    'del autor (authored), el aplicado por energía (applied) y la medición que '
    'lo justifica. Entra un visual con R5 (no cabe en el presupuesto de 60 fps '
    'y sí en el de 30) y sin violar la regla de pases (R3) en iPhone ni iPad. '
    'No editar los metadata a mano: studio/tool/frame_rate.dart apply escribe '
    'applied y revert devuelve authored.';

const _energyFps = 30;
const _defaultFps = 30;
const _defaultK = 28.47;
const _recordPath = 'energy/frame_rate_record.json';

void main(List<String> arguments) {
  exitCode = runFrameRate(arguments);
}

/// Ejecuta un comando y devuelve el código de salida: 0 bien, 1 deriva o
/// error de datos, 2 uso incorrecto.
int runFrameRate(List<String> arguments, {StringSink? out, StringSink? err}) {
  final output = out ?? stdout;
  final errors = err ?? stderr;
  try {
    final args = _Args.parse(arguments);
    final catalogPath = args.option('--catalog');
    final tool = _FrameRateTool(
      catalogPath == null ? _defaultCatalog() : Directory(catalogPath),
      output,
    );
    switch (args.command) {
      case 'status':
        args.allow(const {'--catalog'});
        return tool.status(checkOnly: false);
      case 'check':
        args.allow(const {'--catalog'});
        return tool.status(checkOnly: true);
      case 'record':
        args.allow(const {
          '--catalog',
          '--from-csv',
          '--base-commit',
          '--date',
          '--k',
        });
        final csv = args.option('--from-csv');
        if (csv == null) throw const _UsageError('Falta --from-csv <archivo>.');
        // El commit medido no se deduce de HEAD: el CSV puede ser de otro.
        final baseCommit = args.option('--base-commit');
        if (baseCommit == null) {
          throw const _UsageError('Falta --base-commit <commit medido>.');
        }
        final k = args.option('--k');
        final parsedK = k == null ? _defaultK : double.tryParse(k);
        if (parsedK == null) throw _UsageError('--k no es un número: $k');
        return tool.record(
          File(csv),
          baseCommit: baseCommit,
          date: args.option('--date'),
          k: parsedK,
        );
      case 'apply':
      case 'revert':
        args.allow(const {'--catalog', '--ids', '--all'});
        return tool.write(args, apply: args.command == 'apply');
      default:
        throw _UsageError('Comando desconocido: ${args.command}');
    }
  } on _UsageError catch (error) {
    errors
      ..writeln(error.message)
      ..write(frameRateUsage);
    return 2;
  } on _ToolError catch (error) {
    errors.writeln(error.message);
    return 1;
  }
}

Directory _defaultCatalog() {
  final studio = File.fromUri(Platform.script).parent.parent;
  return Directory('${studio.parent.path}/packages/visual_catalog');
}

class _UsageError implements Exception {
  const _UsageError(this.message);
  final String message;
}

class _ToolError implements Exception {
  const _ToolError(this.message);
  final String message;
}

class _Args {
  _Args(this.command, this._options);

  factory _Args.parse(List<String> arguments) {
    if (arguments.isEmpty) throw const _UsageError('Falta el comando.');
    final options = <String, String?>{};
    for (var i = 1; i < arguments.length; i++) {
      final name = arguments[i];
      if (!name.startsWith('--')) {
        throw _UsageError('Argumento inesperado: $name');
      }
      if (options.containsKey(name)) throw _UsageError('$name repetido.');
      if (name == '--all') {
        options[name] = null;
      } else {
        if (i + 1 >= arguments.length)
          throw _UsageError('Falta el valor de $name.');
        options[name] = arguments[++i];
      }
    }
    return _Args(arguments.first, options);
  }

  final String command;
  final Map<String, String?> _options;

  void allow(Set<String> names) {
    for (final name in _options.keys) {
      if (!names.contains(name)) {
        throw _UsageError('$command no acepta $name.');
      }
    }
  }

  String? option(String name) => _options[name];
  bool flag(String name) => _options.containsKey(name);
}

class _Entry {
  _Entry(this.json, this.authored, this.applied);

  factory _Entry.fromJson(String id, Object? json) {
    if (json is! Map<String, Object?>) {
      throw _ToolError('$_recordPath: $id no es un objeto.');
    }
    int fps(String key) {
      final value = json[key];
      if (value is! int || (value != 30 && value != 60)) {
        throw _ToolError('$_recordPath: $id.$key debe ser 30 o 60.');
      }
      return value;
    }

    return _Entry(json, fps('authored'), fps('applied'));
  }

  final Map<String, Object?> json;
  final int authored;
  final int applied;
}

class _Record {
  _Record(this.policy, this.entries);

  final String policy;
  final SplayTreeMap<String, _Entry> entries;

  String encode() {
    final json = {
      'policy': policy,
      'visuals': {for (final e in entries.entries) e.key: e.value.json},
    };
    return '${const JsonEncoder.withIndent('  ').convert(json)}\n';
  }
}

/// Una línea `framesPerSecond: 30|60` (o su ausencia, que vale 30).
class _Metadata {
  _Metadata(this.path, this.content) : lines = content.split('\n') {
    final count = 'framesPerSecond'.allMatches(content).length;
    if (count > 1) {
      throw _ToolError(
        '$path: framesPerSecond aparece $count veces; debe ser una.',
      );
    }
    if (count == 1) {
      index = lines.indexWhere((line) => line.contains('framesPerSecond'));
      if (_match == null) {
        throw _ToolError(
          '$path: la línea de framesPerSecond debe ser '
          '"framesPerSecond: 30," o "framesPerSecond: 60,".',
        );
      }
    }
    if (content.contains(frameRateMarker) && !marked) {
      throw _ToolError(
        '$path: la marca de energía está fuera de framesPerSecond.',
      );
    }
  }

  static final _line = RegExp(r'^(\s*framesPerSecond:\s*)(30|60)\b(.*)$');
  static final _reactivity = RegExp(r'^(\s*)reactivity:');

  final String path;
  final String content;
  final List<String> lines;
  int? index;

  static String _body(String line) =>
      line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
  static String _cr(String line) => line.endsWith('\r') ? '\r' : '';

  RegExpMatch? get _match {
    final i = index;
    return i == null ? null : _line.firstMatch(_body(lines[i]));
  }

  bool get explicit => index != null;
  int get fps => _match == null ? _defaultFps : int.parse(_match!.group(2)!);
  bool get marked => _match?.group(3)!.endsWith(' $frameRateMarker') ?? false;

  /// El mismo archivo con [target] y la marca indicada; nada más cambia.
  String withFps(int target, {required bool marked}) {
    final next = List.of(lines);
    final suffix = marked ? ' $frameRateMarker' : '';
    final match = _match;
    if (match == null) {
      if (target == _defaultFps) return content;
      final at = next.indexWhere(_reactivity.hasMatch);
      if (at < 0 || !_body(next[at]).trimRight().endsWith(',')) {
        throw _ToolError(
          '$path: falta la línea "reactivity: …," para insertar framesPerSecond.',
        );
      }
      final indent = _reactivity.firstMatch(next[at])!.group(1)!;
      next.insert(
        at + 1,
        '${indent}framesPerSecond: $target,$suffix${_cr(next[at])}',
      );
      return next.join('\n');
    }
    var rest = match.group(3)!;
    if (rest.endsWith(' $frameRateMarker')) {
      rest = rest.substring(0, rest.length - frameRateMarker.length - 1);
    }
    final i = index!;
    next[i] = '${match.group(1)}$target$rest$suffix${_cr(next[i])}';
    return next.join('\n');
  }
}

class _FrameRateTool {
  _FrameRateTool(this.catalog, this.out);

  final Directory catalog;
  final StringSink out;

  File get _recordFile => File('${catalog.path}/$_recordPath');
  Directory get _visuals => Directory('${catalog.path}/lib/visuals');
  File _metadataFile(String id) => File('${_visuals.path}/${id}_metadata.dart');

  _Metadata _readMetadata(String id) {
    final file = _metadataFile(id);
    if (!file.existsSync()) {
      throw _ToolError('Falta lib/visuals/${id}_metadata.dart.');
    }
    return _Metadata('${id}_metadata.dart', file.readAsStringSync());
  }

  _Record _loadRecord() {
    final file = _recordFile;
    if (!file.existsSync()) return _Record(frameRatePolicy, SplayTreeMap());
    final Object? json;
    try {
      json = jsonDecode(file.readAsStringSync());
    } on FormatException catch (error) {
      throw _ToolError('$_recordPath no es JSON válido: ${error.message}');
    }
    if (json is! Map<String, Object?> ||
        json['visuals'] is! Map<String, Object?>) {
      throw const _ToolError('$_recordPath debe tener "visuals": {…}.');
    }
    final visuals = json['visuals']! as Map<String, Object?>;
    final policy = json['policy'];
    return _Record(
      policy is String ? policy : frameRatePolicy,
      SplayTreeMap.of({
        for (final e in visuals.entries) e.key: _Entry.fromJson(e.key, e.value),
      }),
    );
  }

  /// `status` lista cada visual registrado; `check` sólo las inconsistencias.
  int status({required bool checkOnly}) {
    final record = _loadRecord();
    final problems = <String>[];
    var applied = 0;
    var authored = 0;
    if (!checkOnly) {
      out.writeln('${'id'.padRight(28)} autor aplicado metadata estado');
    }
    for (final MapEntry(key: id, value: entry) in record.entries.entries) {
      String state;
      int? fps;
      try {
        final metadata = _readMetadata(id);
        fps = metadata.fps;
        state = _state(entry, metadata);
      } on _ToolError catch (error) {
        state = error.message;
      }
      if (state == 'aplicado') {
        applied++;
      } else if (state == 'autor') {
        authored++;
      } else {
        problems.add('$id: $state');
      }
      if (!checkOnly) {
        out.writeln(
          '${id.padRight(28)} ${'${entry.authored}'.padRight(5)} '
          '${'${entry.applied}'.padRight(8)} ${'${fps ?? '-'}'.padRight(8)} $state',
        );
      }
    }
    if (_visuals.existsSync()) {
      final marked = <String>[];
      for (final file in _visuals.listSync().whereType<File>()) {
        final name = file.uri.pathSegments.last;
        if (!name.endsWith('_metadata.dart')) continue;
        final id = name.substring(0, name.length - '_metadata.dart'.length);
        if (!record.entries.containsKey(id) &&
            file.readAsStringSync().contains(frameRateMarker)) {
          marked.add(
            '$id: tiene la marca de energía pero no está en el registro',
          );
        }
      }
      problems.addAll(marked..sort());
    }
    if (checkOnly) problems.forEach(out.writeln);
    out.writeln(
      '${record.entries.length} visuales en $_recordPath: $applied aplicados, '
      '$authored con el valor del autor, ${problems.length} inconsistencias.',
    );
    return checkOnly && problems.isNotEmpty ? 1 : 0;
  }

  /// "aplicado", "autor" o la descripción de la inconsistencia.
  String _state(_Entry entry, _Metadata metadata) {
    final fps = metadata.fps;
    final differs = entry.applied != entry.authored;
    if (differs && fps == entry.applied) {
      return !metadata.explicit || metadata.marked
          ? 'aplicado'
          : 'vale ${entry.applied} sin la marca de energía';
    }
    if (fps == entry.authored) {
      return metadata.marked
          ? 'tiene la marca con el valor del autor'
          : 'autor';
    }
    return 'vale $fps: no es el del autor (${entry.authored}) '
        'ni el aplicado (${entry.applied})';
  }

  int write(_Args args, {required bool apply}) {
    final record = _loadRecord();
    final all = args.flag('--all');
    final idsOption = args.option('--ids');
    if (all == (idsOption != null)) {
      throw const _UsageError('Indica --ids a,b o --all.');
    }
    final ids =
        all
            ? record.entries.keys.toList()
            : idsOption!
                .split(',')
                .where((id) => id.isNotEmpty)
                .toSet()
                .toList();
    final unknown = ids.where((id) => !record.entries.containsKey(id)).toList();
    if (unknown.isNotEmpty) {
      throw _UsageError('No están en $_recordPath: ${unknown.join(', ')}');
    }
    final changes = <String, String>{};
    for (final id in ids) {
      final entry = record.entries[id]!;
      final metadata = _readMetadata(id);
      final target = apply ? entry.applied : entry.authored;
      final next = metadata.withFps(
        target,
        marked: apply && entry.applied != entry.authored,
      );
      if (next != metadata.content) changes[id] = next;
    }
    // Todo se valida antes de escribir: un error no deja el catálogo a medias.
    for (final MapEntry(key: id, value: content) in changes.entries) {
      _metadataFile(id).writeAsStringSync(content, flush: true);
    }
    out.writeln(
      '${apply ? 'apply' : 'revert'}: ${changes.length} metadata cambiados, '
      '${ids.length - changes.length} ya estaban al día.',
    );
    return 0;
  }

  int record(
    File csv, {
    required String baseCommit,
    required String? date,
    required double k,
  }) {
    if (!csv.existsSync()) throw _ToolError('No existe ${csv.path}.');
    final rows = _parseCsv(csv.readAsStringSync());
    if (rows.isEmpty) throw const _ToolError('El CSV está vacío.');
    final header = rows.first;
    const columns = [
      'id',
      'fps',
      'R5_should_be_30fps',
      'R3_passes_violation_iphone',
      'R3_passes_violation_ipad',
      'gpu_ms_iphone_est',
      'cpu_ms_p50',
      'rounds',
    ];
    final column = {for (final name in columns) name: header.indexOf(name)};
    final missing = [
      for (final e in column.entries)
        if (e.value < 0) e.key,
    ];
    if (missing.isNotEmpty) {
      throw _ToolError('Faltan columnas en el CSV: ${missing.join(', ')}');
    }
    final record = _loadRecord();
    final entries = SplayTreeMap.of(record.entries);
    final errors = <String>[];
    final excluded = <String>[];
    final candidates = <String>[];
    var added = 0;
    var updated = 0;
    var removed = 0;
    final day = date ?? _today();
    for (final row in rows.skip(1)) {
      if (row.length == 1 && row.single.isEmpty) continue;
      if (row.length != header.length) {
        errors.add(
          'Fila con ${row.length} columnas (se esperaban ${header.length}).',
        );
        continue;
      }
      String value(String name) => row[column[name]!].trim();
      final id = value('id');
      final passes =
          value('R3_passes_violation_iphone') == '0' &&
          value('R3_passes_violation_ipad') == '0';
      final existing = entries[id];
      final measured = int.tryParse(value('fps'));
      final gpu = double.tryParse(value('gpu_ms_iphone_est'));
      final cpu = double.tryParse(value('cpu_ms_p50'));
      // El harness sólo marca R5 en filas medidas a 60 fps. Una medición hecha
      // con el valor ya aplicado se decide con las cifras por cuadro.
      final atApplied =
          existing != null &&
          existing.applied != existing.authored &&
          measured == existing.applied;
      if (atApplied && (gpu == null || cpu == null)) {
        errors.add('$id: gpu_ms_iphone_est o cpu_ms_p50 no válidos.');
        continue;
      }
      final fits60 = atApplied && _fitsBudget(60, gpu!, cpu!);
      final r5 =
          atApplied
              ? !fits60 && _fitsBudget(30, gpu!, cpu!)
              : value('R5_should_be_30fps') == '1';
      if (!(r5 && passes)) {
        if (r5) excluded.add(id);
        if (existing == null) continue;
        try {
          if (_state(existing, _readMetadata(id)) == 'aplicado') {
            if (fits60) {
              // No se revierte solo: lo decide una persona con `revert`.
              candidates.add(id);
            } else {
              errors.add(
                '$id: ya no cumple la regla y está aplicado; '
                'primero: dart run tool/frame_rate.dart revert --ids $id',
              );
            }
            continue;
          }
        } on _ToolError catch (error) {
          errors.add(error.message);
          continue;
        }
        entries.remove(id);
        removed++;
        continue;
      }
      final rounds = RegExp(r'(g\d+)(?:\.\d+)?:').allMatches(value('rounds'));
      if ((measured != 30 && measured != 60) ||
          gpu == null ||
          cpu == null ||
          rounds.isEmpty) {
        errors.add(
          '$id: fps, gpu_ms_iphone_est, cpu_ms_p50 o rounds no válidos.',
        );
        continue;
      }
      final int fps;
      try {
        fps = _readMetadata(id).fps;
      } on _ToolError catch (error) {
        errors.add(error.message);
        continue;
      }
      final authored = existing?.authored ?? measured!;
      final applied = existing?.applied ?? _energyFps;
      if (existing == null
          ? fps != measured
          : measured != authored && measured != applied) {
        errors.add(
          '$id: se midió a $measured fps pero el metadata vale $fps; '
          'vuelve a medir o revisa el registro.',
        );
        continue;
      }
      if (authored == _energyFps) continue;
      entries[id] = _Entry(
        {
          'authored': authored,
          'applied': _energyFps,
          'reason': frameRateReason,
          'gpuIphoneEstMs': gpu,
          'cpuMs': cpu,
          'K': k,
          'round': rounds.last.group(1),
          'baseCommit': baseCommit,
          'date': day,
        },
        authored,
        _energyFps,
      );
      if (existing == null) {
        added++;
      } else {
        updated++;
      }
    }
    if (errors.isNotEmpty) throw _ToolError(errors.join('\n'));
    _recordFile.parent.createSync(recursive: true);
    _recordFile.writeAsStringSync(
      _Record(record.policy, entries).encode(),
      flush: true,
    );
    out.writeln(
      'record: ${entries.length} visuales en $_recordPath '
      '($added nuevos, $updated actualizados, $removed quitados).',
    );
    if (excluded.isNotEmpty) {
      out.writeln('Excluidos por pases (R3): ${(excluded..sort()).join(', ')}');
    }
    if (candidates.isNotEmpty) {
      final ids = (candidates..sort()).join(',');
      out
        ..writeln(
          'Ya caben en 60 fps y siguen aplicados (no se revierten solos): '
          '${candidates.join(', ')}',
        )
        ..writeln(
          'Para devolver el valor del autor: '
          'dart run tool/frame_rate.dart revert --ids $ids',
        );
    }
    out.writeln(
      'Para escribir el valor: dart run tool/frame_rate.dart apply --all',
    );
    return 0;
  }

  static String _today() {
    final now = DateTime.now();
    String two(int n) => '$n'.padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)}';
  }
}

/// Presupuesto por cuadro del harness de energía (aggregate.py): a 60 fps,
/// GPU <= 4 ms y CPU <= 2 ms; a 30 fps, GPU <= 8 ms y CPU <= 4 ms.
bool _fitsBudget(int fps, double gpuMs, double cpuMs) =>
    fps == 60 ? gpuMs <= 4 && cpuMs <= 2 : gpuMs <= 8 && cpuMs <= 4;

/// CSV con comillas dobles (RFC 4180): comas y saltos dentro de comillas.
List<List<String>> _parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (quoted) {
      if (char == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(char);
      }
    } else if (char == '"') {
      quoted = true;
    } else if (char == ',') {
      row.add(field.toString());
      field.clear();
    } else if (char == '\n') {
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = <String>[];
    } else if (char != '\r') {
      field.write(char);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}
