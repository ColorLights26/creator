import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:audiovisual_creator/readiness/creator_readiness.dart';
import 'package:audiovisual_creator/team_review/visual_revision.dart';
import 'package:crypto/crypto.dart';
import 'package:scene_compositor/authoring.dart';
import 'package:scene_compositor/creator_build_manifest.dart';
import 'package:scene_compositor/creator_device_card_evidence.dart';

/// Registro técnico de candidatos del catálogo Creator.
///
/// Separa tres hechos que la aprobación mezclaba: el estado técnico de un
/// visual (este registro), la nota estética del equipo (Chic Team, por
/// revisión) y la selección para la app (`creator_review.dart approve`).
///
/// `prepare` ejecuta o ingiere las pruebas que ya existen (sanitizers y
/// replay, barrido de modificadores, gate de pasadas, escena y conducta en
/// Metal, shaders antiguos, harness Mac) y las ata a una identidad técnica
/// exacta: revisión de voto + programa compilado + SDK/ABI + runtime iOS +
/// herramientas de prueba + perfil de superficie. Ningún estado «comprobado»
/// sale de una compilación, de una estimación Mac ni de un voto: exige la
/// ficha medida en el dispositivo de referencia o en un perfil con
/// calibración sostenida propia, para esa misma identidad y alcance.
/// Evidence identifies the binary that was measured, separately from the
/// verifier that reads it. Only these two build-time evidence consumers may
/// change without invalidating that binary. Every other source hash, runtime,
/// SDK, compiler, check, surface, resource and contract must remain identical.
Map<String, Object?> resolveCreatorEvidenceManifest(
  Map<String, Object?> current,
  Map<String, Object?>? bundled,
) {
  const verifierPaths = {
    'packages/scene_compositor/lib/creator_device_card_evidence.dart',
    'studio/tool/readiness.dart',
  };
  Map<String, Object?> receipt(List<String> changed) => {
    'policy': 'isolated-sustained-envelope-v2',
    'sourceManifestHash': current['hash'],
    'measuredManifestHash': bundled?['hash'],
    'changedVerifierInputs': changed,
    'verifierHashes': {
      for (final path in verifierPaths)
        path: ((current['engine'] as Map)['buildInputs'] as Map)['files'][path],
    },
  };
  Map<String, Object?> unchanged() => {
    'manifest': current,
    'bundledMatches': false,
    'verification': receipt(const []),
  };
  if (bundled == null || current['schemaVersion'] != bundled['schemaVersion']) {
    return unchanged();
  }
  bool coherent(Map<String, Object?> manifest) {
    final engine = manifest['engine'];
    if (engine is! Map ||
        manifest['hash'] != _sha256Text(_canonicalJson(engine)))
      return false;
    final inputs = engine['buildInputs'];
    return inputs is Map &&
        inputs['files'] is Map &&
        inputs['hash'] == _sha256Text(_canonicalJson(inputs['files']));
  }

  if (!coherent(current) || !coherent(bundled)) return unchanged();
  final live = Map<String, Object?>.from(current['engine'] as Map);
  final old = bundled['engine'] as Map;
  final inputs = Map<String, Object?>.from(live['buildInputs'] as Map);
  final files = Map<String, Object?>.from(inputs['files'] as Map);
  final oldFiles = (old['buildInputs'] as Map)['files'] as Map;
  if (files.length != oldFiles.length ||
      !files.keys.every(oldFiles.containsKey))
    return unchanged();
  final changed =
      files.keys.where((path) => files[path] != oldFiles[path]).toList()
        ..sort();
  if (changed.any((path) => !verifierPaths.contains(path))) return unchanged();
  for (final path in changed) {
    files[path] = oldFiles[path];
  }
  inputs['files'] = files;
  inputs['hash'] = _sha256Text(_canonicalJson(files));
  live['buildInputs'] = inputs;
  if (_canonicalJson(live) != _canonicalJson(old)) return unchanged();
  // The sealed measured manifest is returned intact, never rewritten.
  return {
    'manifest': bundled,
    'bundledMatches': true,
    'verification': receipt(changed),
  };
}

const readinessUsage = '''
Uso (desde studio/):
  dart run tool/readiness.dart status [--json] [--author <nombre>]
  dart run tool/readiness.dart prepare --evidence <carpeta>
      [--run-checks] [--run-harness <carpeta del harness>]
      [--harness-rounds <jsonl>:<catálogo.json>:<raíz del runtime>[,…]]
      [--device-cards <json>] [--energy-contract <scene_energy_budget_v1.json>]
      [--authors-from-git]
  Sin --device-cards usa readiness/device_cards.json si existe (lo escribe
    cards import). Cada ficha se vuelve a leer de su fila y su log (hash
    comprobado) para esta identidad técnica, el contrato registrado, el
    dispositivo y su calibración, su cadencia y su perfil; lo que falta o no
    coincide deja «pendiente».
  dart run tool/readiness.dart contract import <scene_energy_budget_v1.json>
      Copia DATA del contrato (readiness/energy_contract.json): revisión, hash
      semántico, procedencia y los valores que esta herramienta consume.
  dart run tool/readiness.dart cards import --rows <energy_probe.jsonl>[,…]
      [--out readiness/device_cards.json]
      Fichas desde las filas medidas de energy_probe.py (modo creator) y sus
      logs de consola; nadie escribe números a mano.
  dart run tool/readiness.dart links status
  dart run tool/readiness.dart links propose --base <commit> [--captures <carpeta>]
  dart run tool/readiness.dart links review <id> --from <rev> --to <rev>
      --reviewer <nombre> [--reject] [--note <texto>]
Opción común: --catalog <ruta de packages/visual_catalog>.
''';

const readinessPolicy =
    'Un visual está comprobado sólo cuando todas las pruebas Mac pasan y su '
    'ficha medida, para esta misma identidad técnica, queda dentro del techo '
    'de su slot en la referencia o de un ancla sostenida propia en otro '
    'dispositivo. El alcance indica dispositivo, alimentación, brillo y '
    'ajustes; otro dispositivo no equivale al iPhone. Compilar, estimar en la Mac '
    'o recibir votos no lo comprueba. Pendiente de evidencia: falta esa ficha '
    'o alguna prueba no corrió (la estimación Mac, aunque no alcance 30 fps, '
    'solo marca prioridad de medición). Necesita reparación: una prueba Mac '
    'falló (replay, barrido, pasadas o Metal) o el harness registró un cuadro '
    'por encima del freno de producción; una estimación nunca lo decide. '
    'El estado técnico nunca decide la nota del equipo ni la aprobación.';

const _registryPath = 'readiness/registry.json';
const _studioExportPath = 'readiness/studio_readiness.json';
const _linksPath = 'readiness/revision_links.json';
const _contractPath = 'readiness/energy_contract.json';
const _cardsPath = 'readiness/device_cards.json';
const _attributionPath = 'readiness/attribution.json';
const _checksMetaName = 'checks.meta.json';

/// Fichas del iPhone 14 Pro que calibran la estimación Mac (sonda de
/// energía, lote 2026-10-06/07, `energy_probe_batch.jsonl`, ids
/// b_creator_plasma_scene y b_creator_synthwave_scene, 30 fps). Dos puntos:
/// la estimación sólo sirve para ordenar y detectar lo claramente inviable.
const _deviceAnchors = {
  'plasma_scene': {
    'gpuMsPerFrame': 94.61 / 30,
    'efficiencyCorePercent': 34.35,
    'renderThreadPercent': 17.8,
  },
  'synthwave_scene': {
    'gpuMsPerFrame': 205.30 / 30,
    'efficiencyCorePercent': 68.14,
    'renderThreadPercent': 52.1,
  },
};
const _canvasEfficiencyCorePercent = 6.31;

/// Relación medida/estimación más favorable observada en el teléfono
/// (`measuredToMacEstimateRatioMinimum` del contrato; la copia registrada
/// manda, este valor sólo sirve si no hay copia).
const _fallbackMostFavourableRatio = 0.75;

const _referenceCardDescription =
    'una fila de la sonda de energía (minibase/tool/energy_probe.py, modo '
    'creator sobre Visual Studio) del visual solo, perfil, señal sintética '
    'fuerte, sin gobernador de energía, con warmup; GPU de la app por segundo, '
    'CPU en núcleos E y S, fps logrados';

void main(List<String> arguments) {
  exitCode = runReadiness(arguments);
}

/// Código de salida: 0 bien, 1 datos o fallo, 2 uso incorrecto.
int runReadiness(List<String> arguments, {StringSink? out, StringSink? err}) {
  final output = out ?? stdout;
  final errors = err ?? stderr;
  try {
    final args = _Args.parse(arguments);
    final catalogPath = args.option('--catalog');
    final tool = ReadinessTool(
      catalogPath == null ? _defaultCatalog() : Directory(catalogPath),
      output,
    );
    switch (args.command) {
      case 'status':
        args.allow(const {'--catalog', '--json', '--author'});
        return tool.status(
          json: args.flag('--json'),
          author: args.option('--author'),
        );
      case 'prepare':
        args.allow(const {
          '--catalog',
          '--evidence',
          '--run-checks',
          '--run-harness',
          '--harness-rounds',
          '--device-cards',
          '--energy-contract',
          '--authors-from-git',
          '--studio',
        });
        final evidence = args.option('--evidence');
        if (evidence == null)
          throw const _UsageError('Falta --evidence <carpeta>.');
        return tool.prepare(
          Directory(evidence),
          runChecks: args.flag('--run-checks'),
          harness: args.option('--run-harness'),
          harnessRounds: args.option('--harness-rounds'),
          deviceCards: args.option('--device-cards'),
          energyContract: args.option('--energy-contract'),
          authorsFromGit: args.flag('--authors-from-git'),
          studio: args.option('--studio'),
        );
      case 'links':
        return _links(tool, args);
      case 'contract':
        args.allow(const {'--catalog'});
        if (args.positional.length != 2 || args.positional.first != 'import') {
          throw const _UsageError(
            'contract import <scene_energy_budget_v1.json>',
          );
        }
        return tool.contractImport(File(args.positional[1]));
      case 'cards':
        args.allow(const {'--catalog', '--rows', '--out'});
        final rows = args.option('--rows');
        if (args.positional.length != 1 ||
            args.positional.first != 'import' ||
            rows == null) {
          throw const _UsageError(
            'cards import --rows <jsonl>[,…] [--out <json>]',
          );
        }
        return tool.cardsImport(
          rows.split(',').map((path) => File(path.trim())).toList(),
          out: args.option('--out'),
        );
      default:
        throw _UsageError('Comando desconocido: ${args.command}');
    }
  } on _UsageError catch (error) {
    errors
      ..writeln(error.message)
      ..write(readinessUsage);
    return 2;
  } on _ToolError catch (error) {
    errors.writeln(error.message);
    return 1;
  }
}

int _links(ReadinessTool tool, _Args args) {
  final sub = args.positional.isEmpty ? '' : args.positional.first;
  switch (sub) {
    case 'status':
      args.allow(const {'--catalog'});
      return tool.linksStatus();
    case 'propose':
      args.allow(const {'--catalog', '--base', '--captures'});
      final base = args.option('--base');
      if (base == null) throw const _UsageError('Falta --base <commit>.');
      return tool.linksPropose(base, captures: args.option('--captures'));
    case 'review':
      args.allow(const {
        '--catalog',
        '--from',
        '--to',
        '--reviewer',
        '--reject',
        '--note',
      });
      if (args.positional.length != 2) {
        throw const _UsageError(
          'links review <id> --from … --to … --reviewer …',
        );
      }
      final from = args.option('--from'), to = args.option('--to');
      final reviewer = args.option('--reviewer');
      if (from == null || to == null || reviewer == null) {
        throw const _UsageError('Faltan --from, --to o --reviewer.');
      }
      return tool.linksReview(
        args.positional[1],
        from: from,
        to: to,
        reviewer: reviewer,
        reject: args.flag('--reject'),
        note: args.option('--note') ?? '',
      );
    default:
      throw const _UsageError('links admite status, propose o review.');
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
  _Args(this.command, this.positional, this._options);

  factory _Args.parse(List<String> arguments) {
    if (arguments.isEmpty) throw const _UsageError('Falta el comando.');
    final options = <String, String?>{};
    final positional = <String>[];
    for (var i = 1; i < arguments.length; i++) {
      final name = arguments[i];
      if (!name.startsWith('--')) {
        positional.add(name);
        continue;
      }
      if (options.containsKey(name)) throw _UsageError('$name repetido.');
      if (_flags.contains(name)) {
        options[name] = null;
      } else {
        if (i + 1 >= arguments.length) {
          throw _UsageError('Falta el valor de $name.');
        }
        options[name] = arguments[++i];
      }
    }
    return _Args(arguments.first, positional, options);
  }

  static const _flags = {
    '--json',
    '--run-checks',
    '--authors-from-git',
    '--reject',
  };

  final String command;
  final List<String> positional;
  final Map<String, String?> _options;

  void allow(Set<String> names) {
    for (final name in _options.keys) {
      if (!names.contains(name)) throw _UsageError('$command no acepta $name.');
    }
  }

  String? option(String name) => _options[name];
  bool flag(String name) => _options.containsKey(name);
}

String _sha256(List<int> bytes) => sha256.convert(bytes).toString();
String _sha256Text(String text) => _sha256(utf8.encode(text));

String _canonicalJson(Object? value) => jsonEncode(_sorted(value));
Object? _sorted(Object? value) => switch (value) {
  Map<Object?, Object?>() => {
    for (final key in value.keys.map((key) => '$key').toList()..sort())
      key: _sorted(value[key]),
  },
  List<Object?>() => [for (final item in value) _sorted(item)],
  _ => value,
};

String _encode(Object? json) =>
    '${const JsonEncoder.withIndent('  ').convert(json)}\n';

void _writeText(File file, String contents) {
  if (file.existsSync() && file.readAsStringSync() == contents) return;
  file.parent.createSync(recursive: true);
  final temporary = File('${file.path}.$pid.tmp')
    ..writeAsStringSync(contents, flush: true);
  temporary.renameSync(file.path);
}

Map<String, Object?> _readJsonObject(File file, String what) {
  if (!file.existsSync()) throw _ToolError('Falta $what: ${file.path}');
  final Object? json;
  try {
    json = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    throw _ToolError('${file.path} no es JSON válido: ${error.message}');
  }
  if (json is! Map<String, Object?>) {
    throw _ToolError('${file.path} debe ser un objeto JSON.');
  }
  return json;
}

double _percentile(List<double> values, double q) {
  if (values.isEmpty) return double.nan;
  final sorted = [...values]..sort();
  final k = (sorted.length - 1) * q;
  final low = k.floor(), high = math.min(low + 1, sorted.length - 1);
  return sorted[low] + (sorted[high] - sorted[low]) * (k - low);
}

String _round(double value, [int digits = 2]) =>
    value.isNaN ? '—' : value.toStringAsFixed(digits);

/// Un resultado de prueba con lo que demuestra y lo que no.
class _Check {
  _Check(this.status, {this.detail = '', this.data = const {}});

  _Check.notRun([String reason = 'no corrió']) : this('notRun', detail: reason);
  _Check.notApplicable([String reason = 'no aplica'])
    : this('notApplicable', detail: reason);

  final String
  status; // pass | warn | fail | info | notRun | notApplicable | pending | within | exceeds
  final String detail;
  final Map<String, Object?> data;

  bool get failed => status == 'fail';
  bool get missing => status == 'notRun';

  Map<String, Object?> toJson(String proves, String doesNotProve) => {
    'status': status,
    if (detail.isNotEmpty) 'detail': detail,
    ...data,
    'proves': proves,
    'doesNotProve': doesNotProve,
  };
}

/// Lo que cada prueba demuestra y no demuestra, declarado una sola vez.
const _proves = {
  'admission': (
    'la pareja código/metadata pasa la admisión y el lint de Creator y el '
        'catálogo generado la incluye',
    'nada sobre coste, calor ni calidad',
  ),
  'nativeReplay': (
    'ASan/UBSan sin errores; dibuja algo; mismo dibujo con la misma semilla; '
        'dos instancias no comparten estado; sin música, la misma cantidad de '
        'figuras y el mismo movimiento a 30 y a 60 fps; los valores iniciales '
        'de los modificadores no cambian el dibujo',
    'coste en el teléfono, calor, calidad perceptual ni píxeles entre GPUs',
  ),
  'modifierSweep': (
    'con música fuerte, cada modificador cambia el dibujo en sus extremos, '
        'opciones y variaciones; un cambio en vivo; mismo movimiento a 30/60 '
        'fps con valores no iniciales; ningún extremo revienta el presupuesto',
    'que el cambio sea bueno ni que el usuario lo vaya a ver (la app aún no '
        'expone modificadores)',
  ),
  'passGate': (
    'con los valores iniciales, 12 s de música fuerte y 2 s de silencio a su '
        'fps: pasadas intermedias ≤ 35 en iPhone (664×1440) y ≤ 28 en iPad '
        '(900×1296), bytes retenidos ≤ 128 MiB (mismo contador que Metal, 0 '
        'diferencias en 277 visuales). Avisa si los ajustes al máximo o una '
        'variación pasan de 28 en iPad',
    'tiempo de GPU ni CPU en el teléfono',
  ),
  'metalScene': (
    'compila y dibuja en Metal (Mac): continuidad al cambiar tamaño, '
        'controles y reacción, rollback y nueva semilla; alpha; replay de estado',
    'igualdad de píxeles entre GPUs ni coste',
  ),
  'metalBehavior': (
    'con historias idénticas: un visual music/optional difiere entre música '
        'y neutro; con reacción apagada o sin autorización musical dibuja lo '
        'neutro; uno none no cambia',
    'calidad ni intensidad de la reacción',
  ),
  'hostCost': (
    'coste por cuadro en la Mac (M-series, 664×1440 MSAA 4×) y una estimación '
        'del iPhone 14 Pro calibrada con dos fichas reales; sirve para ordenar '
        'la cola física y detectar lo claramente inviable',
    'la ficha del teléfono: el factor medido/estimado observado va de 0,75× '
        'a 1,85×',
  ),
  'metalShader': (
    'el shader antiguo compila con el Metal real de la Mac y dibuja píxeles '
        'visibles; sondas sintéticas al mismo instante: música, silencio, no '
        'disponible y reacción apagada',
    'igualdad de píxeles entre GPUs ni coste',
  ),
  'deviceCard': (
    'ficha medida en el iPhone de referencia para esta identidad técnica '
        'comparada con el techo de su slot (GPU/s, CPU en núcleos E, '
        'núcleos S)',
    'calor sostenido en combinación: eso lo cubre el soak de la escena',
  ),
};

/// The registered copy of the app's energy contract
/// (`readiness/energy_contract.json`): a DATA file with the contract's
/// revision, its semantic hash (sorted canonical JSON of the whole contract),
/// where it came from and exactly the values this tool consumes. Creator never
/// depends on the app checkout: `contract import` (or `prepare
/// --energy-contract`) refreshes the copy; without a copy nothing certifies.
class _ContractCopy {
  _ContractCopy(this.json);

  final Map<String, Object?> json;

  String get revision => '${json['revision']}';
  String get semanticHash => '${json['semanticHash']}';
  Map<String, Object?> get _values =>
      json['values'] as Map<String, Object?>? ?? const {};
  Map<String, Object?> _section(String name) =>
      _values[name] as Map<String, Object?>? ?? const {};
  double? _number(String section, String key) =>
      (_section(section)[key] as num?)?.toDouble();

  /// Slot ceilings per role (`background`, `overlay`); null when the
  /// contract has no measured ceiling for that field.
  Map<String, double>? ceiling(String role) {
    final slot = _section('slotCeilings')[role];
    if (slot is! Map) return null;
    final gpu = slot['gpuMsPerSecond'], e = slot['efficiencyCorePercent'];
    if (gpu is! num || e is! num) return null;
    return {
      'gpuMsPerSecond': gpu.toDouble(),
      'efficiencyCorePercent': e.toDouble(),
    };
  }

  double get gpuMarginPercent => _number('comparison', 'gpuMarginPercent') ?? 0;
  double get efficiencyCoreMarginPercent =>
      _number('comparison', 'efficiencyCoreMarginPercent') ?? 0;
  double? get performanceCorePercentBound =>
      _number('comparison', 'performanceCorePercentOfCoreBound');
  double? get warmupSeconds => _number('protocol', 'measurementWarmupSeconds');
  double? get cpuWindowSecondsMinimum =>
      _number('protocol', 'measurementCpuWindowSecondsMinimum');
  double? get gpuWindowSeconds =>
      _number('protocol', 'measurementGpuWindowSeconds');
  String get referenceIdentifier =>
      '${_section('reference')['identifier'] ?? ''}';
  String get referenceModel => '${_section('reference')['model'] ?? ''}';
  String get referenceOperatingSystem =>
      '${_section('reference')['operatingSystem'] ?? ''}';
  int? get referenceSurfaceWidth =>
      (_section('reference')['surfaceWidth'] as num?)?.toInt();
  int? get referenceSurfaceHeight =>
      (_section('reference')['surfaceHeight'] as num?)?.toInt();
  double get mostFavourableRatio =>
      _number('macEstimate', 'measuredToMacEstimateRatioMinimum') ??
      _fallbackMostFavourableRatio;
  String get creatorFeasibilityRule =>
      '${_section('creatorProgram')['feasibilityRule'] ?? ''}';

  /// What the registry records about the contract in force.
  Map<String, Object?> stamp({
    String? livePath,
    String? liveSemanticHash,
    String? liveRevision,
  }) => {
    'revision': revision,
    'semanticHash': semanticHash,
    'source': json['source'],
    'importedAt': json['importedAt'],
    if (livePath != null) 'livePath': livePath,
    if (liveRevision != null) 'liveRevision': liveRevision,
    if (liveSemanticHash != null) 'liveSemanticHash': liveSemanticHash,
    if (liveSemanticHash != null)
      'matchesLive': liveSemanticHash == semanticHash,
  };

  /// Builds the copy from the live contract: only values this tool reads,
  /// each from its documented place, plus the semantic hash of everything.
  static Map<String, Object?> extract(
    Map<String, Object?> contract,
    File from,
  ) {
    Object? at(List<String> path) {
      Object? node = contract;
      for (final key in path) {
        if (node is! Map) return null;
        node = node[key];
      }
      return node;
    }

    num? value(List<String> path) {
      final node = at(path);
      if (node is Map && node['value'] is num) return node['value'] as num;
      return node is num ? node : null;
    }

    String? text(List<String> path) {
      final node = at(path);
      if (node is Map && node['value'] is String)
        return node['value'] as String;
      return node is String ? node : null;
    }

    Map<String, Object?>? slot(String name, String gpuKey, String eKey) {
      final gpu = value(['slotCeilings', 'slots', name, 'measured', gpuKey]);
      final e = value(['slotCeilings', 'slots', name, 'measured', eKey]);
      if (gpu == null || e == null) return null;
      return {
        'gpuMsPerSecond': gpu,
        'efficiencyCorePercent': e,
        'basis': {'gpu': gpuKey, 'efficiencyCore': eKey},
      };
    }

    final revision = contract['revision'];
    if (revision is! String || revision.isEmpty) {
      throw const _ToolError('El contrato de energía no declara revision.');
    }
    return {
      'schemaVersion': 1,
      'revision': revision,
      'semanticHash': _sha256Text(_canonicalJson(contract)),
      'source': from.path,
      'sourceFileSha256': _sha256(from.readAsBytesSync()),
      'importedAt': DateTime.now().toUtc().toIso8601String(),
      'values': {
        // A card measured alone (Studio, no canvas) compares with the raw
        // ceilings: the costliest element of the slot, canvas included.
        'slotCeilings': {
          'background': slot(
            'backgroundProgram',
            'appGpuMsPerSecond',
            'efficiencyCorePercentOfCore',
          ),
          'overlay': slot(
            'overlayProgram',
            'appGpuMsPerSecond',
            'efficiencyCorePercentOfCore',
          ),
        },
        'comparison': {
          for (final key in [
            'gpuMarginPercent',
            'efficiencyCoreMarginPercent',
            'performanceCorePercentOfCoreBound',
          ])
            key: value(['slotCeilings', 'comparison', key]),
        },
        'protocol': {
          for (final key in [
            'measurementWarmupSeconds',
            'measurementCpuWindowSecondsMinimum',
            'measurementGpuWindowSeconds',
            'measurementSurfaceWidth',
            'measurementSurfaceHeight',
            'measurementMsaaSamples',
          ])
            key: value(['elements', 'catalogProgram', 'requirements', key]),
        },
        'macEstimate': {
          for (final key in [
            'measuredToMacEstimateRatioMinimum',
            'measuredToMacEstimateRatioMaximum',
            'macToReferenceFactor',
          ])
            key: value(['elements', 'catalogProgram', 'requirements', key]),
        },
        'creatorProgram': {
          'feasibilityRule': text([
            'elements',
            'creatorProgram',
            'requirements',
            'feasibilityRule',
          ]),
          for (final key in [
            'defaultFramesPerSecond',
            'maximumFramesPerSecond',
            'maximumIntermediatePassesAtReference',
            'maximumIntermediatePassesAtIpad',
            'runtimeMaximumPasses',
            'runtimeMaximumRetainedBytes',
          ])
            key: value(['elements', 'creatorProgram', 'requirements', key]),
        },
        'reference': {
          'model': text(['reference', 'device', 'model']),
          'identifier': text(['reference', 'device', 'identifier']),
          'operatingSystem': text(['reference', 'device', 'operatingSystem']),
          'surfaceWidth': value(['reference', 'surface', 'width']),
          'surfaceHeight': value(['reference', 'surface', 'height']),
          'certificationSoakMinutes': value([
            'reference',
            'measurementConditions',
            'certificationSoakMinutes',
          ]),
        },
      },
    };
  }
}

class _Host {
  _Host({
    required this.cpuThreadMs,
    required this.gpuMs,
    required this.wallMs,
    required this.nativeMs,
    required this.passesMax,
    required this.retainedMb,
    required this.failFrames,
    required this.clean,
    required this.file,
    this.error = '',
  });

  final double cpuThreadMs, gpuMs, wallMs, nativeMs, retainedMb;
  final int passesMax, failFrames;
  final bool clean;
  final String file;
  final String error;
}

/// Estimación lineal con dos anclas; null cuando faltan.
class _Model {
  _Model(this.gpu, this.efficiency, this.render);

  /// (a, b): valor del dispositivo = a + b × valor de la Mac.
  final (double, double) gpu, efficiency, render;

  static (double, double) _fit((double, double) p, (double, double) s) {
    final b = (s.$2 - p.$2) / (s.$1 - p.$1);
    return (p.$2 - b * p.$1, b);
  }

  static _Model? fit(Map<String, _Host> hosts) {
    final p = hosts['plasma_scene'], s = hosts['synthwave_scene'];
    if (p == null || s == null || p.error.isNotEmpty || s.error.isNotEmpty) {
      return null;
    }
    if (p.gpuMs == s.gpuMs || p.cpuThreadMs == s.cpuThreadMs) return null;
    final ap = _deviceAnchors['plasma_scene']!,
        as = _deviceAnchors['synthwave_scene']!;
    return _Model(
      _fit((p.gpuMs, ap['gpuMsPerFrame']!), (s.gpuMs, as['gpuMsPerFrame']!)),
      _fit(
        (
          p.cpuThreadMs,
          (ap['efficiencyCorePercent']! - _canvasEfficiencyCorePercent) / 3,
        ),
        (
          s.cpuThreadMs,
          (as['efficiencyCorePercent']! - _canvasEfficiencyCorePercent) / 3,
        ),
      ),
      _fit(
        (p.cpuThreadMs, ap['renderThreadPercent']! / 3),
        (s.cpuThreadMs, as['renderThreadPercent']! / 3),
      ),
    );
  }

  /// Estimación a [fps]: GPU ms por cuadro y por segundo, CPU en núcleos E
  /// (% de un núcleo), ms del hilo de render por cuadro.
  Map<String, double> at(_Host host, int fps, String role) {
    final gpuFrame = gpu.$1 + gpu.$2 * host.gpuMs;
    final ePer10 = efficiency.$1 + efficiency.$2 * host.cpuThreadMs;
    final rPer10 = render.$1 + render.$2 * host.cpuThreadMs;
    final renderPercent = rPer10 * fps / 10;
    final renderMsFrame = renderPercent / 100 * 1000 / fps;
    var e = ePer10 * fps / 10;
    if (role == 'background') e += _canvasEfficiencyCorePercent;
    return {
      'gpuMsPerFrame': gpuFrame,
      'gpuMsPerSecond': gpuFrame * fps,
      'efficiencyCorePercent': e,
      'renderThreadMsPerFrame': renderMsFrame,
      'frameMs': gpuFrame + renderMsFrame,
      'budgetMs': 1000 / fps,
    };
  }
}

class ReadinessTool {
  ReadinessTool(this.catalog, this.out);

  final Directory catalog;
  final StringSink out;

  File get _registryFile => File('${catalog.path}/$_registryPath');
  File get _studioFile => File('${catalog.path}/$_studioExportPath');
  File get _linksFile => File('${catalog.path}/$_linksPath');
  Directory get _repo => catalog.parent.parent;

  // --- Catálogo -------------------------------------------------------------

  List<CreatorVisualDefinition> _definitions() {
    final runtime = File('${catalog.path}/assets/creator_catalog.json');
    final metadata = File('${catalog.path}/assets/catalog_metadata.json');
    for (final file in [runtime, metadata]) {
      if (!file.existsSync()) {
        throw _ToolError(
          'Falta ${file.path}. Ejecuta dart run tool/compile_visuals.dart.',
        );
      }
    }
    try {
      return decodeCreatorCatalog(
        runtimeJson: runtime.readAsStringSync(),
        metadataJson: metadata.readAsStringSync(),
      );
    } on Object catch (error) {
      throw _ToolError('El catálogo generado no se pudo leer: $error');
    }
  }

  String _catalogSha() => _sha256(
    File('${catalog.path}/assets/creator_catalog.json').readAsBytesSync(),
  );

  String _git(List<String> args, {bool allowFailure = false}) {
    final result = Process.runSync('git', ['-C', _repo.path, ...args]);
    if (result.exitCode != 0) {
      if (allowFailure) return '';
      throw _ToolError('git ${args.join(' ')}: ${result.stderr}');
    }
    return (result.stdout as String).trim();
  }

  String _catalogCommit() {
    final head = _git(['rev-parse', 'HEAD'], allowFailure: true);
    if (head.isEmpty) return 'sin git';
    final dirty = _git([
      'status',
      '--porcelain',
      '--',
      'packages/visual_catalog/lib',
      'packages/scene_program_native/src',
      'packages/scene_compositor',
    ], allowFailure: true);
    return dirty.isEmpty ? head : '$head-dirty';
  }

  // --- Identidad del motor --------------------------------------------------

  /// The resolved package that owns the SDK and the material compiler: the
  /// repo's `studio` when it is resolved, else the package this tool runs in.
  Directory _host() {
    final studio = Directory('${_repo.path}/studio');
    if (File('${studio.path}/.dart_tool/package_config.json').existsSync()) {
      return studio;
    }
    final config = Platform.packageConfig;
    if (config != null) {
      final file = File.fromUri(Uri.parse(config));
      if (file.existsSync()) return file.parent.parent;
    }
    // flutter test exposes no package config URI: the package it runs in.
    if (File(
      '${Directory.current.path}/.dart_tool/package_config.json',
    ).existsSync()) {
      return Directory.current;
    }
    throw const _ToolError(
      'No se encuentra un paquete resuelto (studio/.dart_tool): ejecuta flutter pub get en studio.',
    );
  }

  /// The complete build identity (`creator_build_manifest.dart`): SDK/ABI,
  /// runtime Swift of the Creator path, material compiler, resources, checks,
  /// surfaces and the contract copy. `buildHash` is what every consumer
  /// compares. A verifier-only upgrade keeps that sealed measured identity
  /// and records current verifier hashes separately; renderer changes cannot.
  Map<String, Object?> _engine(List<CreatorVisualDefinition> visuals) {
    final manifest = creatorBuildManifest(
      repo: _repo,
      host: _host(),
      catalog: catalog,
    );
    final engine = Map<String, Object?>.from(manifest['engine'] as Map);
    final nativeVisual = visuals.where((v) => v.isNative).firstOrNull;
    final catalogSdk = nativeVisual?.nativeBuild['sdkHash'];
    if (catalogSdk != null && catalogSdk != engine['sdkHash']) {
      throw _ToolError(
        'El catálogo generado se compiló con otro SDK nativo ($catalogSdk ≠ '
        '${engine['sdkHash']}): ejecuta dart run tool/compile_visuals.dart.',
      );
    }
    final bundled = readCreatorBuildManifest(catalog);
    final resolved = resolveCreatorEvidenceManifest(manifest, bundled);
    final measured = resolved['manifest'] as Map<String, Object?>;
    return {
      'buildHash': measured['hash'],
      'manifest': measured['engine'],
      'bundledManifestHash': bundled?['hash'],
      'bundledManifestMatches':
          resolved['bundledMatches'] == true &&
          bundled?['hash'] == measured['hash'],
      'verification': resolved['verification'],
      'creatorPathRuntimeHash': _creatorPathRuntimeHash(_repo),
    };
  }

  /// SHA-256 of the program the device actually runs for [visual]: the
  /// compiled native program, or the shader source of an old visual.
  static String programHash(CreatorVisualDefinition visual) =>
      visual.isNative
          ? '${visual.nativeBuild['hash']}'
          : _sha256Text(visual.shaderSource);

  /// What the harness and the Metal scene checks actually compile:
  /// `SceneCatalog*.swift`, the signal frame and the production output
  /// allocator. A measurement from another checkout is valid only when this
  /// hash and the program hash both match.
  static final _allocatorPattern = RegExp(
    r'@available\(iOS 15\.0, \*\)\n(?:private )?final class SceneSurfaceNativeOutputAllocator \{.*?^\}',
    multiLine: true,
    dotAll: true,
  );

  String _creatorPathRuntimeHash(Directory root) {
    final runtime = Directory(
      '${root.path}/packages/scene_compositor/ios/Classes/Runtime',
    );
    if (!runtime.existsSync()) {
      throw _ToolError('Falta el runtime iOS en ${root.path}');
    }
    final swift =
        runtime
            .listSync(followLinks: false)
            .whereType<File>()
            .where(
              (f) => RegExp(r'/SceneCatalog[^/]*\.swift$').hasMatch(f.path),
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final buffer = StringBuffer();
    for (final file in [
      ...swift,
      File('${runtime.path}/SceneRenderSignalFrameV2.swift'),
    ]) {
      buffer
        ..writeln(file.uri.pathSegments.last)
        ..writeln(_sha256(file.readAsBytesSync()));
    }
    final surface = File('${runtime.path}/SceneRenderV2ImageSurface.swift');
    final allocator =
        surface.existsSync()
            ? _allocatorPattern.firstMatch(surface.readAsStringSync())?.group(0)
            : null;
    buffer.writeln(
      allocator == null ? 'allocator:none' : _sha256Text(allocator),
    );
    return _sha256Text(buffer.toString()).substring(0, 16);
  }

  String _technicalIdentity(
    CreatorVisualDefinition visual,
    String revision,
    Map<String, Object?> engine,
  ) {
    return _sha256Text(
      _canonicalJson({
        'revision': revision,
        'nativeHash': visual.isNative ? visual.nativeBuild['hash'] : null,
        'imageHashes':
            visual.isNative ? visual.nativeBuild['imageHashes'] : null,
        'materials': visual.isNative ? visual.nativeBuild['materials'] : null,
        'framesPerSecond': visual.framesPerSecond,
        'role': visual.role.name,
        'reactivity': visual.reactivity.name,
        'engine': engine,
      }),
    ).substring(0, 16);
  }

  // --- Pruebas Mac ----------------------------------------------------------

  static const _checkLogs = {
    'native': 'check_native_strict.log',
    'passReport': 'check_native_pass_report.log',
    'metal': 'check_creator_scenes.log',
    'shaders': 'check_creator_catalog.log',
  };

  void _runChecks(Directory checks, String buildHash) {
    checks.createSync(recursive: true);
    final generated = '${_repo.path}/studio/build/creator_native';
    if (!File('$generated/creator_programs.inc').existsSync()) {
      throw const _ToolError(
        'Falta studio/build/creator_native: ejecuta dart run tool/compile_visuals.dart.',
      );
    }
    final catalogJson = '${catalog.path}/assets/creator_catalog.json';
    final commands = <String, List<String>>{
      'native': [
        'python3',
        'packages/scene_program_native/test/check_native.py',
        '--generated',
        generated,
        '--strict-modifiers',
      ],
      'passReport': [
        'python3',
        'packages/scene_program_native/test/check_native.py',
        '--generated',
        generated,
        '--pass-report',
        'harness',
      ],
      'metal': [
        'python3',
        'packages/scene_compositor/ios/Tests/check_creator_scenes.py',
        '--generated',
        generated,
        '--catalog',
        catalogJson,
        '--output',
        '${checks.path}/metal_renders',
      ],
      'shaders': [
        'ruby',
        'packages/scene_compositor/ios/Tests/check_creator_catalog.rb',
        catalogJson,
        '--admission',
      ],
    };
    final started = DateTime.now().toUtc();
    final exits = <String, int>{};
    for (final entry in commands.entries) {
      out.writeln('Ejecutando ${entry.key}: ${entry.value.join(' ')}');
      final result = Process.runSync(
        entry.value.first,
        entry.value.sublist(1),
        workingDirectory: _repo.path,
      );
      exits[entry.key] = result.exitCode;
      _writeText(
        File('${checks.path}/${_checkLogs[entry.key]}'),
        '${result.stdout}\n${result.stderr}',
      );
      out.writeln('  salida ${result.exitCode}');
    }
    _writeText(
      File('${checks.path}/$_checksMetaName'),
      _encode({
        'catalogSha256': _catalogSha(),
        'buildHash': buildHash,
        'catalogCommit': _catalogCommit(),
        'startedAt': started.toIso8601String(),
        'finishedAt': DateTime.now().toUtc().toIso8601String(),
        'exitCodes': exits,
        'commands': {
          for (final e in commands.entries) e.key: e.value.join(' '),
        },
      }),
    );
  }

  static final _passReplay = RegExp(
    r'^PASS authored CPU creator_([a-z0-9_]+): (.*)$',
  );
  static final _passSweep = RegExp(
    r'^PASS modifiers creator_([a-z0-9_]+): (.*)$',
  );
  static final _passGate = RegExp(
    r'^PASS passes creator_([a-z0-9_]+): iPhone (\d+) \(máx (\d+)\), iPad (\d+) \(máx (\d+)\)$',
  );
  static final _warnGate = RegExp(r'^WARN passes creator_([a-z0-9_]+): (.*)$');
  static final _warnOrFail = RegExp(r'^(WARN|FAIL) ([a-z][a-z0-9_]*): (.*)$');
  static final _passesReport = RegExp(
    r'^PASSES creator_([a-z0-9_]+) fps (\d+) iPhone (\d+) (\d+) iPad (\d+) (\d+)$',
  );
  static final _passContinuity = RegExp(
    r'^PASS continuity creator_([a-z0-9_]+):',
  );
  static final _passMetal = RegExp(
    r'^PASS authored creator_([a-z0-9_]+): (.*)$',
  );
  static final _passBehavior = RegExp(
    r'^PASS behavior creator_([a-z0-9_]+): (.*)$',
  );
  static final _failureMention = RegExp(r'creator_([a-z0-9_]+): ([^"\\]+)');

  Map<String, Map<String, _Check>> _parseChecks(
    Directory checks,
    List<CreatorVisualDefinition> visuals,
  ) {
    final results = {
      for (final visual in visuals)
        visual.id: <String, _Check>{
          'admission': _Check(
            'pass',
            detail: 'incluido en el catálogo generado',
          ),
        },
    };
    List<String> lines(String key) {
      final file = File('${checks.path}/${_checkLogs[key]}');
      return file.existsSync()
          ? const LineSplitter().convert(file.readAsStringSync())
          : const [];
    }

    // Sanitizers, replay 30/60, barrido estricto y gate de pasadas.
    final native = lines('native');
    final gateWarnings = <String, List<String>>{};
    final sweepWarnings = <String, List<String>>{};
    final fails = <String, List<String>>{};
    for (final line in native) {
      if (_passReplay.firstMatch(line) case final m?) {
        results[m[1]!]?['nativeReplay'] = _Check('pass', detail: m[2]!);
      } else if (_passSweep.firstMatch(line) case final m?) {
        results[m[1]!]?['modifierSweep'] = _Check('pass', detail: m[2]!);
      } else if (_passGate.firstMatch(line) case final m?) {
        results[m[1]!]?['passGate'] = _Check(
          'pass',
          data: {
            'iPhone': {'passes': int.parse(m[2]!), 'limit': int.parse(m[3]!)},
            'iPad': {'passes': int.parse(m[4]!), 'limit': int.parse(m[5]!)},
          },
        );
      } else if (_warnGate.firstMatch(line) case final m?) {
        (gateWarnings[m[1]!] ??= []).add(m[2]!);
      } else if (_warnOrFail.firstMatch(line) case final m?) {
        final id = m[2]!, text = m[3]!;
        if (m[1] == 'WARN') {
          (sweepWarnings[id] ??= []).add(text);
        } else {
          (fails[id] ??= []).add(text);
        }
      }
    }
    for (final id in results.keys) {
      final visual = visuals.firstWhere((v) => v.id == id);
      final checks = results[id]!;
      if (!visual.isNative) {
        checks['nativeReplay'] = _Check.notApplicable('shader antiguo');
        checks['modifierSweep'] = _Check.notApplicable('shader antiguo');
        checks['passGate'] = _Check.notApplicable('shader antiguo');
        continue;
      }
      for (final text in fails[id] ?? const <String>[]) {
        final key =
            text.contains('modificador')
                ? 'modifierSweep'
                : text.contains('pasadas') || text.contains('MiB')
                ? 'passGate'
                : 'nativeReplay';
        checks[key] = _Check('fail', detail: text);
      }
      if (visual.modifiers.isEmpty && visual.variations.isEmpty) {
        checks['modifierSweep'] ??= _Check.notApplicable('sin modificadores');
      }
      final warnings = gateWarnings[id];
      if (warnings != null && checks['passGate']?.status == 'pass') {
        final gate = checks['passGate']!;
        checks['passGate'] = _Check(
          'warn',
          detail: warnings.join(' | '),
          data: {...gate.data, 'warnings': warnings},
        );
      }
      final dead = sweepWarnings[id];
      if (dead != null && checks['modifierSweep']?.status == 'pass') {
        checks['modifierSweep'] = _Check('warn', detail: dead.join(' | '));
      }
      checks['nativeReplay'] ??= _Check.notRun();
      checks['modifierSweep'] ??= _Check.notRun();
      checks['passGate'] ??= _Check.notRun();
    }
    // Tabla de pasadas con el calendario del harness (240 cuadros).
    for (final line in lines('passReport')) {
      if (_passesReport.firstMatch(line) case final m?) {
        final checks = results[m[1]!];
        final gate = checks?['passGate'];
        if (checks == null || gate == null || gate.status == 'notApplicable')
          continue;
        checks['passGate'] = _Check(
          gate.status,
          detail: gate.detail,
          data: {
            ...gate.data,
            'harnessSchedule': {
              'fps': int.parse(m[2]!),
              'iPhone': {'passes': int.parse(m[3]!), 'bytes': int.parse(m[4]!)},
              'iPad': {'passes': int.parse(m[5]!), 'bytes': int.parse(m[6]!)},
            },
          },
        );
      }
    }
    // Metal: escenas nativas.
    final metal = lines('metal');
    final metalFailures = <String, String>{};
    final continuity = <String>{};
    for (final line in metal) {
      if (_passContinuity.firstMatch(line) case final m?) {
        continuity.add(m[1]!);
      } else if (_passMetal.firstMatch(line) case final m?) {
        results[m[1]!]?['metalScene'] = _Check('pass', detail: m[2]!);
      } else if (_passBehavior.firstMatch(line) case final m?) {
        results[m[1]!]?['metalBehavior'] = _Check('pass', detail: m[2]!);
      } else if (line.contains('rror')) {
        final m = _failureMention.firstMatch(line);
        if (m != null) metalFailures[m[1]!] = m[2]!.trim();
      }
    }
    // Shaders antiguos.
    for (final line in lines('shaders')) {
      if (_passMetal.firstMatch(line) case final m?) {
        final checks = results[m[1]!];
        if (checks != null &&
            checks['nativeReplay']?.status == 'notApplicable') {
          checks['metalScene'] = _Check('pass', detail: m[2]!);
        }
      } else if (_passBehavior.firstMatch(line) case final m?) {
        final checks = results[m[1]!];
        if (checks != null &&
            checks['nativeReplay']?.status == 'notApplicable') {
          checks['metalBehavior'] = _Check('pass', detail: m[2]!);
        }
      }
    }
    final metalRan = metal.isNotEmpty;
    for (final id in results.keys) {
      final checks = results[id]!;
      final failure = metalFailures[id];
      if (failure != null) {
        checks['metalScene'] ??= _Check('fail', detail: failure);
        checks['metalBehavior'] ??= _Check('fail', detail: failure);
      }
      final stopped = metalRan && metalFailures.isNotEmpty;
      checks['metalScene'] ??= _Check.notRun(
        stopped ? 'la prueba Metal se detuvo en otro visual' : 'no corrió',
      );
      checks['metalBehavior'] ??= _Check.notRun(
        stopped ? 'la prueba Metal se detuvo en otro visual' : 'no corrió',
      );
      if (checks['metalScene']!.status == 'pass' &&
          !continuity.contains(id) &&
          visuals.firstWhere((v) => v.id == id).isNative) {
        checks['metalScene'] = _Check(
          'pass',
          detail: '${checks['metalScene']!.detail} (sin línea de continuidad)',
        );
      }
    }
    return results;
  }

  // --- Harness Mac ----------------------------------------------------------

  /// `<jsonl dir>:<catalog.json>:<runtime root>` rounds measured in another
  /// checkout. A row is taken only when that catalog's program hash for the
  /// id equals the current one and the Creator-path runtime hash matches.
  Map<String, _Host> _parseExternalRounds(
    String spec,
    List<CreatorVisualDefinition> visuals,
    String currentRuntimeHash,
  ) {
    final hosts = <String, _Host>{};
    final current = {for (final v in visuals) v.id: v.nativeBuild['hash']};
    for (final item in spec.split(',')) {
      final parts = item.split(':');
      if (parts.length != 3) {
        throw _ToolError(
          '--harness-rounds espera <jsonl>:<catálogo>:<runtime>, no "$item".',
        );
      }
      final dir = Directory(parts[0]);
      final catalogFile = File(parts[1]);
      final runtimeHash = _creatorPathRuntimeHash(Directory(parts[2]));
      if (runtimeHash != currentRuntimeHash) {
        out.writeln(
          'Ronda ${dir.path}: runtime del camino Creator distinto '
          '($runtimeHash ≠ $currentRuntimeHash); se ignora.',
        );
        continue;
      }
      final Map<String, Object?> roundHashes;
      try {
        final json =
            jsonDecode(catalogFile.readAsStringSync()) as Map<String, Object?>;
        roundHashes = {
          for (final v in json['visuals'] as List)
            if (v is Map && v['kind'] == 'scene')
              v['id'] as String: (v['nativeBuild'] as Map?)?['hash'],
        };
      } on Object catch (error) {
        throw _ToolError(
          'No se pudo leer el catálogo de la ronda ${catalogFile.path}: $error',
        );
      }
      var taken = 0, skipped = 0;
      for (final entry in _parseHarness(dir).entries) {
        final id = entry.key;
        if (!current.containsKey(id) ||
            roundHashes[id] == null ||
            roundHashes[id] != current[id]) {
          skipped++;
          continue;
        }
        final previous = hosts[id];
        if (previous == null || _better(entry.value, previous)) {
          hosts[id] = entry.value;
        }
        taken++;
      }
      out.writeln(
        'Ronda ${dir.path}: $taken filas con el mismo programa y runtime, '
        '$skipped descartadas.',
      );
    }
    return hosts;
  }

  Map<String, _Host> _parseHarness(Directory harnessOut) {
    final hosts = <String, _Host>{};
    if (!harnessOut.existsSync()) return hosts;
    final files = <File>[];
    void collect(Directory dir) {
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is File &&
            entity.path.endsWith('.jsonl') &&
            entity.path.contains('/iphone/')) {
          files.add(entity);
        }
      }
    }

    collect(harnessOut);
    files.sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final metaFile = File(
        file.path.replaceFirst(RegExp(r'\.jsonl$'), '.meta.json'),
      );
      var clean = true;
      if (metaFile.existsSync()) {
        try {
          final meta =
              jsonDecode(metaFile.readAsStringSync()) as Map<String, Object?>;
          // The harness only flags GPU contention; a loaded CPU inflates the
          // canary's thread time too, so both canaries must be at rest.
          clean = meta['clean'] != false && _canariesAtRest(meta);
        } on Object {
          clean = false;
        }
      }
      final lines = const LineSplitter().convert(file.readAsStringSync());
      for (var n = 0; n < lines.length; n++) {
        final line = lines[n];
        if (line.trim().isEmpty) continue;
        final Object? record;
        try {
          record = jsonDecode(line);
        } on FormatException {
          continue;
        }
        if (record is! Map<String, Object?>) continue;
        final id = record['id'] as String?;
        if (id == null) continue;
        if (file.path.contains('/batch_') &&
            id == 'anillos_humo' &&
            (n == 0 || n == lines.length - 1) &&
            lines.length > 1) {
          continue; // canario del harness
        }
        final host = _summarize(record, clean, file.path);
        final previous = hosts[id];
        if (previous == null || _better(host, previous)) hosts[id] = host;
      }
    }
    return hosts;
  }

  /// Canary limits (anillos_humo at rest: GPU ~0.11 ms, CPU ~0.23 ms).
  static const _canaryGpuMs = 0.25, _canaryCpuMs = 0.28;

  static bool _canariesAtRest(Map<String, Object?> meta) {
    bool within(Object? values, double limit) =>
        values is List &&
        values.isNotEmpty &&
        values.every((v) => v is num && v <= limit);
    return within(meta['canary_gpu_p50'], _canaryGpuMs) &&
        (meta['canary_cpu_p50'] == null ||
            within(meta['canary_cpu_p50'], _canaryCpuMs));
  }

  static bool _better(_Host a, _Host b) {
    if (a.error.isEmpty != b.error.isEmpty) return a.error.isEmpty;
    if (a.clean != b.clean) return a.clean;
    return a.gpuMs < b.gpuMs;
  }

  static _Host _summarize(
    Map<String, Object?> record,
    bool clean,
    String file,
  ) {
    final cols = record['cols'];
    if (cols is! Map<String, Object?>) {
      return _Host(
        cpuThreadMs: double.nan,
        gpuMs: double.nan,
        wallMs: double.nan,
        nativeMs: double.nan,
        passesMax: 0,
        retainedMb: 0,
        failFrames: 0,
        clean: clean,
        file: file,
        error: '${record['error'] ?? 'sin datos'}',
      );
    }
    final warmup = (record['warmup'] as num?)?.toInt() ?? 0;
    List<double> col(String key) {
      final values = cols[key];
      if (values is! List) return const [];
      return [for (final v in values.skip(warmup)) (v as num).toDouble()];
    }

    double max(List<double> values) =>
        values.isEmpty ? 0 : values.reduce(math.max);
    return _Host(
      cpuThreadMs: _percentile(col('cpu_thread_ms'), .5),
      gpuMs: _percentile(col('gpu_ms'), .5),
      wallMs: _percentile(col('wall_ms'), .5),
      nativeMs: _percentile(col('native_cpu_ms'), .5),
      passesMax: max(col('dry_passes')).round(),
      retainedMb: max(col('dry_bytes')) / 1048576,
      failFrames: col('failed').fold(0, (sum, v) => sum + v.round()),
      clean: clean,
      file: file,
    );
  }

  void _runHarness(Directory harness, Directory evidence) {
    final env = {
      ...Platform.environment,
      'CE_EXPORT': _repo.path,
      'CE_GENERATED': '${_repo.path}/studio/build/creator_native',
      'CE_BUILD': '${evidence.path}/harness_build',
      'CE_OUT': '${evidence.path}/harness',
      'CE_CATALOG': '${catalog.path}/assets/creator_catalog.json',
    };
    final steps = [
      ['python3', 'build.py'],
      [
        'python3',
        'run_all.py',
        '--round',
        'rd1',
        '--label',
        'iphone',
        '--batch',
        '40',
        '--gate',
        '--px',
        '664x1440',
        '--logical',
        '393x852',
      ],
      [
        'python3',
        'run_all.py',
        '--round',
        'rd1',
        '--label',
        'ipad',
        '--batch',
        '40',
        '--gate',
        '--px',
        '902x1292',
        '--logical',
        '834x1194',
      ],
    ];
    for (final step in steps) {
      out.writeln('Harness: ${step.join(' ')}');
      final result = Process.runSync(
        step.first,
        step.sublist(1),
        workingDirectory: harness.path,
        environment: env,
      );
      _writeText(
        File(
          '${evidence.path}/harness/${step[1].replaceAll('.py', '')}_${step.length > 5 ? step[5] : 'build'}.log',
        ),
        '${result.stdout}\n${result.stderr}',
      );
      if (result.exitCode != 0) {
        throw _ToolError(
          'El harness falló en ${step.join(' ')} (salida ${result.exitCode}).',
        );
      }
    }
  }

  // --- Autoría --------------------------------------------------------------

  Map<String, Object?>? _attributionCache;

  /// Creative attribution (`readiness/attribution.json`): who made each
  /// visual, imported from the maintainer's historical list. The first Git
  /// commit of a migrated file says who committed it, not who created it, so
  /// both facts are kept apart.
  Map<String, Object?> _attribution() {
    if (_attributionCache != null) return _attributionCache!;
    final file = File('${catalog.path}/$_attributionPath');
    if (!file.existsSync()) return _attributionCache = const {};
    final json = _readJsonObject(file, 'la atribución');
    final visuals = json['visuals'];
    return _attributionCache =
        visuals is Map<String, Object?> ? visuals : const {};
  }

  Map<String, Object?> _gitOrigin(String id) {
    final log = _git([
      'log',
      '--diff-filter=A',
      '--format=%an%x09%ad%x09%h',
      '--date=short',
      '--',
      'packages/visual_catalog/lib/visuals/$id.dart',
    ], allowFailure: true);
    if (log.isEmpty) return {'author': '', 'firstDate': '', 'firstCommit': ''};
    final parts = log.split('\n').last.split('\t');
    return {
      'author': parts[0],
      'firstDate': parts.length > 1 ? parts[1] : '',
      'firstCommit': parts.length > 2 ? parts[2] : '',
    };
  }

  /// `author` is the creative author (attribution file); `git` is the
  /// commit that added the file, when asked for.
  Map<String, Object?> _origin(
    String id, {
    Map<String, Object?>? previous,
    required bool fromGit,
  }) {
    final creative = _attribution()[id];
    final git =
        fromGit
            ? _gitOrigin(id)
            : (previous?['git'] is Map
                ? Map<String, Object?>.from(previous!['git'] as Map)
                : null);
    return {
      'author': creative is Map ? '${creative['author'] ?? ''}' : '',
      'authorSource': creative is Map ? 'attribution.json' : '',
      'date': creative is Map ? '${creative['date'] ?? ''}' : '',
      if (git != null) 'git': git,
    };
  }

  // --- Contrato -------------------------------------------------------------

  File get _contractFile => File('${catalog.path}/$_contractPath');
  File get _cardsFile => File('${catalog.path}/$_cardsPath');

  /// The registered contract copy, or null when Creator has none.
  _ContractCopy? _loadContract() {
    if (!_contractFile.existsSync()) return null;
    final json = _readJsonObject(_contractFile, 'la copia del contrato');
    if (json['revision'] is! String ||
        json['semanticHash'] is! String ||
        json['values'] is! Map) {
      throw _ToolError(
        '${_contractFile.path} no es una copia válida del contrato: repite contract import.',
      );
    }
    return _ContractCopy(json);
  }

  /// `contract import <live>`: writes the DATA copy with its semantic hash.
  int contractImport(File live) {
    final json = _readJsonObject(live, 'el contrato de energía');
    final copy = _ContractCopy.extract(json, live);
    _writeText(_contractFile, _encode(copy));
    out.writeln(
      'Contrato ${copy['revision']} (${(copy['semanticHash'] as String).substring(0, 16)}…) '
      'copiado en ${_contractFile.path}. Ejecuta compile_visuals para que el '
      'manifiesto de build lo recoja.',
    );
    return 0;
  }

  /// The contract in force for this run. With `--energy-contract <live>`,
  /// a copy that differs semantically from the live file is refreshed (same
  /// revision with other content included) and every card judged under the
  /// old copy stops certifying.
  (_ContractCopy?, Map<String, Object?>) _resolveContract(String? livePath) {
    var copy = _loadContract();
    if (livePath == null) {
      return (
        copy,
        copy?.stamp() ??
            {
              'status': 'missing',
              'detail':
                  'sin copia del contrato de energía (readiness contract import)',
            },
      );
    }
    final file = File(livePath);
    final live = _readJsonObject(file, 'el contrato de energía');
    final liveHash = _sha256Text(_canonicalJson(live));
    if (copy == null || copy.semanticHash != liveHash) {
      out.writeln(
        copy == null
            ? 'Sin copia del contrato: se importa $livePath.'
            : 'El contrato vivo difiere de la copia registrada (hash semántico '
                '${copy.semanticHash.substring(0, 12)}… → ${liveHash.substring(0, 12)}…, '
                'revisión ${copy.revision} → ${live['revision']}): se refresca la copia; '
                'las fichas juzgadas con la anterior dejan de certificar.',
      );
      _writeText(_contractFile, _encode(_ContractCopy.extract(live, file)));
      copy = _loadContract();
    }
    return (
      copy,
      copy!.stamp(
        livePath: file.path,
        liveSemanticHash: liveHash,
        liveRevision: '${live['revision']}',
      ),
    );
  }

  // --- Fichas del dispositivo ---------------------------------------------

  static const _profileLabels = {
    'default': 'valores iniciales',
    'max': 'todos los ajustes al máximo',
  };

  static String _profileLabel(Map<String, Object?>? profile) {
    final name = '${profile?['name'] ?? ''}';
    if (name == 'variation')
      return 'la variación ${profile?['variation'] ?? '?'}';
    return _profileLabels[name] ?? (name.isEmpty ? 'perfil sin nombre' : name);
  }

  /// `cards import --rows a.jsonl,b.jsonl`: one card per measured row of the
  /// energy probe in creator mode, bound to its row and console log by hash.
  /// Nobody types a number: every value is copied from the row and
  /// re-checked against it on `prepare`.
  int cardsImport(List<File> rowFiles, {String? out}) {
    final visuals = {for (final v in _definitions()) v.id: v};
    final contract = _loadContract();
    final cards = <String, Map<String, Map<String, Object?>>>{};
    var measured = 0, skipped = 0, unknown = 0;
    for (final file in rowFiles) {
      if (!file.existsSync()) throw _ToolError('Falta ${file.path}');
      final fileSha = _sha256(file.readAsBytesSync());
      for (final line in const LineSplitter().convert(
        file.readAsStringSync(),
      )) {
        if (line.trim().isEmpty) continue;
        final Object? row;
        try {
          row = jsonDecode(line);
        } on FormatException {
          skipped++;
          continue;
        }
        if (row is! Map<String, Object?> || row['targetKind'] != 'creator') {
          skipped++;
          continue;
        }
        final creator = row['creator'];
        if (row['status'] != 'measured' || creator is! Map<String, Object?>) {
          skipped++;
          continue;
        }
        final id = '${creator['visualId']}';
        if (!visuals.containsKey(id)) {
          unknown++;
          continue;
        }
        final card = _cardFromRow(row, creator, file, fileSha, contract);
        final profileKey = _profileLabel(
          card['profile'] as Map<String, Object?>?,
        );
        final byProfile = cards.putIfAbsent(id, () => {});
        final previous = byProfile[profileKey];
        if (previous == null ||
            '${(previous['row'] as Map)['utc']}'.compareTo('${row['utc']}') <
                0) {
          byProfile[profileKey] = card;
        }
        measured++;
      }
    }
    final target = out == null ? _cardsFile : File(out);
    _writeText(
      target,
      _encode({
        'schemaVersion': 1,
        'producer': 'readiness cards import',
        'generatedAt': DateTime.now().toUtc().toIso8601String(),
        'rows': [for (final f in rowFiles) f.path],
        'cards': SplayTreeMap<String, Object?>.from({
          for (final entry in cards.entries)
            entry.key: [
              for (final key in entry.value.keys.toList()..sort())
                entry.value[key],
            ],
        }),
      }),
    );
    this.out.writeln(
      'Fichas: $measured filas medidas de ${cards.length} visuales '
      '(${cards.values.fold(0, (n, c) => n + c.length)} perfiles); '
      '$skipped filas no medidas o ajenas, $unknown de visuales que no están '
      'en el catálogo. Archivo: ${target.path}',
    );
    return 0;
  }

  Map<String, Object?> _cardFromRow(
    Map<String, Object?> row,
    Map<String, Object?> creator,
    File file,
    String fileSha,
    _ContractCopy? contract,
  ) {
    String? consoleSha, probeSha, probePath;
    final consoleLog = row['consoleLog'];
    if (consoleLog is String && File(consoleLog).existsSync()) {
      consoleSha = _sha256(File(consoleLog).readAsBytesSync());
      // The producer's snapshot of the same lines with host time.
      probePath = probeSnapshotPathFor(consoleLog);
      if (File(probePath).existsSync()) {
        probeSha = _sha256(File(probePath).readAsBytesSync());
      }
    }
    Object? copy(String key) => row[key];
    return {
      'visualId': creator['visualId'],
      'profile': creator['profile'],
      'programHash': creator['programHash'],
      'revision': creator['revision'],
      'buildHash': creator['buildHash'],
      'framesPerSecond': creator['framesPerSecond'],
      'reactive': creator['reactive'],
      'signal': creator['signal'],
      'role': creator['role'],
      'host': 'studio',
      'device': row['device'],
      'viewport': row['viewport'],
      'surfacePx': row['surfacePx'],
      'row': {
        'file': file.path,
        'fileSha256': fileSha,
        'id': row['id'],
        'scheduleIndex': row['scheduleIndex'],
        'utc': row['utc'],
        'status': row['status'],
      },
      'log': {'file': consoleLog, 'sha256': consoleSha},
      'probe': {'file': probePath, 'sha256': probeSha},
      'traceEvidence': row['traceEvidence'],
      'protocol': {
        'warmupSeconds': copy('warmupS'),
        'cpuWindowSeconds': copy('traceSpanS'),
        'gpuWindowSeconds': copy('gpuSpanS'),
        'startThermal': copy('startThermal'),
        'thermalStates': copy('thermalStates'),
        'energyLevel': copy('energyLevel'),
        'charging': copy('charging'),
        'lowPower': copy('lowPower'),
        'probeSamples': copy('probeSamples'),
      },
      'measured': {
        'achievedFps': copy('achievedFps'),
        'gpuAppMsPerSecond': copy('gpuAppMsPerSecond'),
        'gpuAppMsPerPublishedFrame': copy('gpuAppMsPerPublishedFrame'),
        'efficiencyCorePercent': copy('runnerEPercent'),
        'performanceCorePercent': copy('runnerSPercent'),
        'renderThreadPercent': copy('renderThreadPercent'),
        'memMb': copy('memMb'),
      },
      'warnings': copy('warnings'),
      'energyContract':
          contract == null
              ? null
              : {
                'revision': contract.revision,
                'semanticHash': contract.semanticHash,
              },
    };
  }

  /// Explicit device profiles (`readiness/device_profiles.json`, DATA keyed
  /// by hardware identifier) for measurements outside the reference device;
  /// none registered means only the contract reference exists.
  Map<String, Object?> _deviceProfiles() {
    final file = File('${_cardsFile.parent.path}/device_profiles.json');
    if (!file.existsSync()) return const {};
    final json = _readJsonObject(file, 'perfiles de dispositivo');
    final devices = json['devices'];
    return devices is Map ? devices.cast<String, Object?>() : const {};
  }

  /// One card checked by the shared evidence validator
  /// (`creator_device_card_evidence.dart`): its row, log and probe snapshot
  /// by hash and content, this identity, the contract copy, the explicit
  /// device, the protocol windows, the trace link and the cadence. Returns
  /// the check (within | exceeds | pending) with the profile it covers.
  _Check _validateCard(
    Map<String, Object?> card,
    CreatorVisualDefinition visual,
    String revision,
    String buildHash,
    _ContractCopy? contract,
  ) {
    final label = _profileLabel(card['profile'] as Map<String, Object?>?);
    final verdict = validateCreatorDeviceCard(
      card: card,
      identity: CreatorCardIdentity(
        visualId: visual.id,
        programHash: programHash(visual),
        revision: revision,
        buildHash: buildHash,
        framesPerSecond: visual.framesPerSecond,
        reactive: visual.reactivity != CreatorReactivity.none,
        native: visual.isNative,
        role: visual.role.name,
        controls: visual.controls.toMap(),
        modifiers: visual.modifierDefaults,
      ),
      contractCopy: contract?.json,
      profileLabel: label,
      deviceProfiles: _deviceProfiles(),
    );
    return _Check(
      verdict.status,
      detail: verdict.detail,
      data: {
        'profile': label,
        if (verdict.status != 'pending') 'measured': verdict.measured,
        if (verdict.status != 'pending') 'row': card['row'],
        if (verdict.status != 'pending') 'host': card['host'],
        if (verdict.device.isNotEmpty) 'device': verdict.device,
        if (verdict.scope.isNotEmpty) 'deviceScope': verdict.scope,
      },
    );
  }

  /// The visual's device evidence: its cards checked one by one. `within`
  /// needs the initial-values profile within its ceiling; the coverage lists
  /// every profile that is within, and nothing is assumed about the rest.
  _Check _deviceCards(
    List<Map<String, Object?>> cards,
    CreatorVisualDefinition visual,
    String revision,
    String buildHash,
    _ContractCopy? contract,
  ) {
    if (cards.isEmpty) {
      return _Check(
        'pending',
        detail:
            contract == null
                ? 'sin ficha del dispositivo y sin copia del contrato de energía'
                : 'sin ficha del dispositivo para esta identidad técnica',
      );
    }
    final results = [
      for (final card in cards)
        _validateCard(card, visual, revision, buildHash, contract),
    ];
    final profiles = [
      for (final r in results)
        {'profile': r.data['profile'], 'status': r.status, 'detail': r.detail},
    ];
    _Check? initial;
    for (final r in results) {
      if (r.data['profile'] == _profileLabels['default']) initial = r;
    }
    final covered = [
      for (final r in results)
        if (r.status == 'within') '${r.data['profile']}',
    ]..sort(
      (a, b) =>
          a == _profileLabels['default']
              ? -1
              : b == _profileLabels['default']
              ? 1
              : a.compareTo(b),
    );
    final deviceScope = initial?.data['deviceScope'];
    final coverage =
        '${deviceScope != null && deviceScope != 'referencia' ? '$deviceScope: ' : ''}${covered.join('; ')}';
    final data = {'profiles': profiles, 'coverage': coverage};
    if (initial == null) {
      return _Check(
        'pending',
        detail:
            'sin ficha con los valores iniciales (${results.map((r) => r.detail).join(' | ')})',
        data: data,
      );
    }
    if (initial.status == 'within') {
      return _Check(
        'within',
        detail: '${initial.detail}; alcance: $coverage',
        data: data,
      );
    }
    return _Check(initial.status, detail: initial.detail, data: data);
  }

  _Check _hostCheck(
    _Host? host,
    _Model? model,
    CreatorVisualDefinition visual,
    _ContractCopy? contract,
  ) {
    if (!visual.isNative) {
      // The Mac harness renders native scenes only; the contract never asked
      // for a Mac estimate, so an old shader is not missing anything here.
      return _Check.notApplicable('el harness Mac sólo mide escenas nativas');
    }
    if (host == null) return _Check.notRun('sin fila del harness');
    if (host.error.isNotEmpty)
      return _Check(
        'fail',
        detail: 'harness: ${host.error}',
        data: {'file': host.file},
      );
    final data = <String, Object?>{
      'cpuThreadMsP50': host.cpuThreadMs,
      'gpuMsP50': host.gpuMs,
      'wallMsP50': host.wallMs,
      'nativeCppMsP50': host.nativeMs,
      'passesMax': host.passesMax,
      'retainedMbMax': host.retainedMb,
      'failFrames': host.failFrames,
      'clean': host.clean,
      'file': host.file,
    };
    if (host.failFrames > 0) {
      return _Check(
        'fail',
        detail:
            'el harness registró ${host.failFrames} cuadros con fallo del presupuesto',
        data: data,
      );
    }
    if (model == null) {
      return _Check(
        'info',
        detail: 'medido en la Mac; sin anclas para estimar el iPhone',
        data: data,
      );
    }
    final role = visual.role.name;
    final ceiling = contract?.ceiling(role);
    if (contract == null || ceiling == null) {
      return _Check(
        'info',
        detail:
            'medido en la Mac; sin copia del contrato con techo para $role, no se estima',
        data: data,
      );
    }
    final ratio = contract.mostFavourableRatio;
    final atFps = model.at(host, visual.framesPerSecond, role);
    final at30 = model.at(host, 30, role);
    bool within(Map<String, double> e) =>
        e['gpuMsPerSecond']! <=
            ceiling['gpuMsPerSecond']! *
                (1 + contract.gpuMarginPercent / 100) &&
        e['efficiencyCorePercent']! <=
            ceiling['efficiencyCorePercent']! *
                (1 + contract.efficiencyCoreMarginPercent / 100);
    bool feasible(Map<String, double> e) => e['frameMs']! <= e['budgetMs']!;
    final String verdict;
    final String detail;
    if (at30['frameMs']! * ratio > at30['budgetMs']!) {
      verdict = 'infeasible';
      detail =
          'estimación a 30 fps: ${_round(at30['frameMs']!, 1)} ms por cuadro '
          '(GPU ${_round(at30['gpuMsPerFrame']!, 1)} + hilo ${_round(at30['renderThreadMsPerFrame']!, 1)}); '
          'ni con el factor más favorable ($ratio×) entra en 33,3 ms';
    } else if (within(atFps) && feasible(atFps)) {
      verdict = 'fits';
      detail =
          'estimación a ${visual.framesPerSecond} fps dentro del techo de su slot';
    } else if (visual.framesPerSecond == 60 && within(at30) && feasible(at30)) {
      verdict = 'fitsAt30';
      detail = 'estimación: no cabe a 60 fps, sí a 30';
    } else {
      verdict = 'verifyOnDevice';
      final why = <String>[];
      if (at30['gpuMsPerSecond']! > ceiling['gpuMsPerSecond']!)
        why.add('GPU ${_round(at30['gpuMsPerSecond']!, 0)} ms/s');
      if (at30['efficiencyCorePercent']! > ceiling['efficiencyCorePercent']!)
        why.add('CPU E ${_round(at30['efficiencyCorePercent']!, 0)}%');
      if (!feasible(at30))
        why.add('${_round(at30['frameMs']!, 1)} ms por cuadro');
      detail =
          'estimación a 30 fps sobre el techo (${why.join(', ')}): medir antes de decidir';
    }
    return _Check(
      'info',
      detail: detail,
      data: {
        ...data,
        'verdict': verdict,
        'estimate': {
          '${visual.framesPerSecond}': {
            for (final e in atFps.entries)
              e.key: double.parse(e.value.toStringAsFixed(2)),
          },
          if (visual.framesPerSecond != 30)
            '30': {
              for (final e in at30.entries)
                e.key: double.parse(e.value.toStringAsFixed(2)),
            },
        },
      },
    );
  }

  (CreatorReadinessState, List<String>, String) _state(
    Map<String, _Check> checks,
  ) {
    final reasons = <String>[];
    final scope = <String>[];
    // needsRepair proviene solo de un fallo PROBADO: una prueba Mac que falló
    // (replay, barrido, gate de pasadas, Metal) o un cuadro del harness por
    // encima del freno de producción (hostCost con estado 'fail'). Una
    // estimación de tiempo en la Mac nunca prueba un fallo ni calentamiento.
    for (final entry in checks.entries) {
      if (entry.value.failed)
        reasons.add('${entry.key}: ${entry.value.detail}');
    }
    if (checks['passGate']?.status == 'warn') {
      scope.add(
        'con los ajustes al máximo o en una variación pasa de 28 pasadas en iPad',
      );
    }
    if (checks['modifierSweep']?.status == 'warn') {
      scope.add('un modificador no cambia nada (la aprobación lo rechaza)');
    }
    // What the Mac checks cover while the card is missing: the initial
    // values, with the notes of the gate and the sweep.
    final macScope =
        scope.isEmpty ? '' : [_profileLabels['default']!, ...scope].join('; ');
    if (reasons.isNotEmpty) {
      return (CreatorReadinessState.needsRepair, reasons, macScope);
    }
    final missing = [
      for (final entry in checks.entries)
        if (entry.value.missing) '${entry.key}: ${entry.value.detail}',
    ];
    final device = checks['deviceCard'];
    if (device?.status == 'exceeds') {
      return (
        CreatorReadinessState.pendingEvidence,
        [
          'deviceCard: ${device!.detail}; necesita una combinación máxima verificada con él o una optimización',
          ...missing,
        ],
        macScope,
      );
    }
    if (device?.status == 'within' && missing.isEmpty) {
      // El alcance comprobado es exactamente el de los perfiles medidos
      // dentro del techo (valores iniciales siempre; máximo y variaciones
      // sólo si su ficha existe y cabe); nunca se extiende por defecto.
      final covered = (device!.data['coverage'] as String?) ?? '';
      final verifiedScope = [
        if (covered.isNotEmpty) covered,
        if (scope.isNotEmpty) scope.join('; '),
      ].join('; ');
      return (
        CreatorReadinessState.verified,
        const [],
        verifiedScope.isEmpty ? _profileLabels['default']! : verifiedScope,
      );
    }
    final why = <String>[
      if (device != null && device.status != 'within')
        'deviceCard: ${device.detail}',
      ...missing,
    ];
    // La estimación Mac es contexto para ordenar la cola física, nunca un
    // fallo: acompaña como prioridad de medición, no bloquea.
    final host = checks['hostCost'];
    if (host != null && host.data['verdict'] != null) {
      why.add('hostCost: ${host.detail}');
    }
    return (CreatorReadinessState.pendingEvidence, why, macScope);
  }

  String _humanDetail(
    CreatorReadinessState state,
    Map<String, _Check> checks,
    List<String> reasons,
  ) {
    switch (state) {
      case CreatorReadinessState.verified:
        return 'Medido dentro del alcance indicado para su dispositivo.';
      case CreatorReadinessState.needsRepair:
        final first = reasons.first;
        final text = first.substring(first.indexOf(':') + 1).trim();
        return text.length > 140 ? '${text.substring(0, 137)}…' : text;
      case CreatorReadinessState.pendingEvidence:
        final missing =
            checks.entries
                .where((e) => e.value.missing && e.key != 'hostCost')
                .map((e) => e.key)
                .toList();
        final verdict = checks['hostCost']?.data['verdict'];
        final hint = switch (verdict) {
          'fits' => 'La estimación Mac cabe; falta la ficha del dispositivo.',
          'fitsAt30' =>
            'La estimación Mac cabe a 30 fps; falta la ficha del dispositivo.',
          'verifyOnDevice' =>
            'La estimación Mac queda sobre el techo: requiere medición física.',
          'infeasible' =>
            'La estimación Mac no alcanza 30 fps (solo estimación, no prueba): '
                'prioridad alta de medición física.',
          _ =>
            checks['deviceCard']?.detail.contains('contrato') == true
                ? 'Falta la copia del contrato de energía (contract import) y la ficha del dispositivo.'
                : 'Falta la ficha del dispositivo.',
        };
        if (missing.isNotEmpty)
          return 'Faltan pruebas Mac (${missing.join(', ')}). $hint';
        final device = checks['deviceCard'];
        final measuredProfiles = device?.data['profiles'];
        if (measuredProfiles is List && measuredProfiles.isNotEmpty) {
          return 'Pasó las pruebas Mac. ${device!.detail}';
        }
        if (checks['deviceCard']?.status == 'exceeds')
          return 'Medido sobre el techo de su slot: necesita verificación en combinación.';
        return 'Pasó las pruebas Mac. $hint';
      case CreatorReadinessState.unknown:
        return '';
    }
  }

  /// SHA-256 of the author pair, so `creator_review.dart` can match the
  /// exact files it validates without recomputing the vote fingerprint.
  Map<String, String> _sourceHashes(String id) {
    String hash(String suffix) {
      final file = File('${catalog.path}/lib/visuals/$id$suffix');
      return file.existsSync() ? _sha256(file.readAsBytesSync()) : '';
    }

    return {'source': hash('.dart'), 'metadata': hash('_metadata.dart')};
  }

  static String _provesKey(String check, CreatorVisualDefinition visual) =>
      !visual.isNative && (check == 'metalScene' || check == 'metalBehavior')
          ? 'metalShader'
          : check;

  // --- prepare --------------------------------------------------------------

  int prepare(
    Directory evidence, {
    required bool runChecks,
    String? harness,
    String? harnessRounds,
    String? deviceCards,
    String? energyContract,
    required bool authorsFromGit,
    String? studio,
  }) {
    final visuals = _definitions();
    final (contract, contractStamp) = _resolveContract(energyContract);
    final engine = _engine(visuals);
    final buildHash = engine['buildHash'] as String;
    if (engine['bundledManifestMatches'] != true) {
      out.writeln(
        'AVISO: el manifiesto de build empaquetado (${engine['bundledManifestHash'] ?? 'ausente'}) '
        'no es el de este motor ($buildHash): ejecuta dart run tool/compile_visuals.dart '
        'o Studio mostrará «cambió el motor».',
      );
    }
    if (contract == null) {
      out.writeln(
        'AVISO: sin copia del contrato de energía (readiness contract import <scene_energy_budget_v1.json>): '
        'ninguna ficha puede certificar.',
      );
    }
    final checksDir = Directory('${evidence.path}/checks');
    final metaFile = File('${checksDir.path}/$_checksMetaName');
    final catalogSha = _catalogSha();
    if (runChecks || !metaFile.existsSync()) {
      if (!runChecks) {
        out.writeln('No hay pruebas en ${checksDir.path}: se ejecutan ahora.');
      }
      _runChecks(checksDir, buildHash);
    }
    final checksMeta = _readJsonObject(metaFile, 'la ficha de las pruebas');
    if (checksMeta['catalogSha256'] != catalogSha) {
      throw _ToolError(
        'Las pruebas de ${checksDir.path} son de otro catálogo '
        '(${checksMeta['catalogSha256']} ≠ $catalogSha). Repite con --run-checks.',
      );
    }
    // A Swift-only engine change keeps the catalog sha: the checks that
    // compile the runtime (Metal) must run again for the new build.
    if (checksMeta['buildHash'] != buildHash) {
      throw _ToolError(
        'Las pruebas de ${checksDir.path} son de otro motor '
        '(manifiesto ${checksMeta['buildHash'] ?? 'sin registrar'} ≠ $buildHash). Repite con --run-checks.',
      );
    }
    if (harness != null) _runHarness(Directory(harness), evidence);
    // A row measured in this evidence folder wins; external rounds fill in
    // only identical programs on the identical Creator-path runtime.
    final hosts = <String, _Host>{};
    if (harnessRounds != null) {
      hosts.addAll(
        _parseExternalRounds(
          harnessRounds,
          visuals,
          engine['creatorPathRuntimeHash'] as String,
        ),
      );
    }
    final own = _parseHarness(Directory('${evidence.path}/harness'));
    for (final entry in own.entries) {
      if (entry.value.error.isEmpty && entry.value.clean) {
        hosts[entry.key] = entry.value;
      } else {
        hosts.putIfAbsent(entry.key, () => entry.value);
      }
    }
    final model = _Model.fit(hosts);
    final cards = _loadCards(deviceCards == null ? null : File(deviceCards));
    final previous =
        _registryFile.existsSync()
            ? _readJsonObject(_registryFile, 'el registro anterior')
            : null;
    final previousVisuals =
        previous?['visuals'] is Map
            ? previous!['visuals'] as Map<String, Object?>
            : <String, Object?>{};
    final parsed = _parseChecks(checksDir, visuals);
    final evidenceFiles = <String, Object?>{};
    for (final entry in _checkLogs.entries) {
      final file = File('${checksDir.path}/${entry.value}');
      if (file.existsSync()) {
        evidenceFiles[entry.key] = {
          'path': file.path,
          'sha256': _sha256(file.readAsBytesSync()),
        };
      }
    }
    evidenceFiles['checksMeta'] = {
      'path': metaFile.path,
      'sha256': _sha256(metaFile.readAsBytesSync()),
    };
    final harnessFiles =
        hosts.values.map((h) => h.file).toSet().toList()..sort();
    if (harnessFiles.isNotEmpty) {
      evidenceFiles['harness'] = [
        for (final path in harnessFiles)
          {'path': path, 'sha256': _sha256(File(path).readAsBytesSync())},
      ];
    }
    final registry = SplayTreeMap<String, Object?>();
    final export = SplayTreeMap<String, Object?>();
    final counts = <CreatorReadinessState, int>{};
    for (final visual in visuals) {
      final revision = visualRevision(visual);
      final identity = _technicalIdentity(visual, revision, engine);
      final checks = parsed[visual.id]!;
      checks['hostCost'] = _hostCheck(
        hosts[visual.id],
        model,
        visual,
        contract,
      );
      final previousEntry = previousVisuals[visual.id];
      // Cards live in readiness/device_cards.json and are re-validated
      // against their rows and logs on every refresh: nothing is carried
      // over from an older registry.
      checks['deviceCard'] = _deviceCards(
        cards[visual.id] ?? const [],
        visual,
        revision,
        buildHash,
        contract,
      );
      final (state, reasons, scope) = _state(checks);
      counts[state] = (counts[state] ?? 0) + 1;
      final origin = _origin(
        visual.id,
        previous:
            previousEntry is Map<String, Object?> &&
                    previousEntry['origin'] is Map<String, Object?>
                ? previousEntry['origin'] as Map<String, Object?>
                : null,
        fromGit: authorsFromGit,
      );
      final detail = _humanDetail(state, checks, reasons);
      final priority = switch (checks['hostCost']?.data['verdict']) {
        'infeasible' => 'medir-primero (estimación no alcanza 30 fps)',
        'verifyOnDevice' =>
          'medir-antes-de-decidir (estimación sobre el techo)',
        'fitsAt30' => 'medir (cabe a 30 fps en la estimación)',
        'fits' => 'medir (cabe en la estimación)',
        _ => null,
      };
      registry[visual.id] = {
        'revision': revision,
        if (priority != null) 'measurementPriority': priority,
        'technicalIdentity': identity,
        'programHash': programHash(visual),
        'sources': _sourceHashes(visual.id),
        'kind': visual.isNative ? 'native' : 'shader',
        'role': visual.role.name,
        'reactivity': visual.reactivity.name,
        'framesPerSecond': visual.framesPerSecond,
        'modifiers': visual.modifiers.length,
        'variations': visual.variations.length,
        'images': visual.images.length,
        'origin': origin,
        'state': state.name,
        'reasons': reasons,
        'scope': scope,
        'detail': detail,
        'checks': {
          for (final entry in checks.entries)
            entry.key: entry.value.toJson(
              _proves[_provesKey(entry.key, visual)]!.$1,
              _proves[_provesKey(entry.key, visual)]!.$2,
            ),
        },
      };
      export[visual.id] =
          CreatorReadinessEntry(
            id: visual.id,
            revision: revision,
            state: state,
            detail: detail,
            scope: scope,
          ).toJson();
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final commit = _catalogCommit();
    _writeText(
      _registryFile,
      _encode({
        'schemaVersion': 1,
        'policy': readinessPolicy,
        'generatedAt': now,
        'catalogCommit': commit,
        'catalogSha256': catalogSha,
        'engine': engine,
        'energyContract': contractStamp,
        'slotCeilings': {
          'background': contract?.ceiling('background'),
          'overlay': contract?.ceiling('overlay'),
          'comparison':
              contract == null
                  ? null
                  : {
                    'gpuMarginPercent': contract.gpuMarginPercent,
                    'efficiencyCoreMarginPercent':
                        contract.efficiencyCoreMarginPercent,
                    'performanceCorePercentOfCoreBound':
                        contract.performanceCorePercentBound,
                  },
        },
        'referenceDevice': {
          'model': contract?.referenceModel,
          'identifier': contract?.referenceIdentifier,
          'operatingSystem': contract?.referenceOperatingSystem,
          'card': _referenceCardDescription,
        },
        'macEstimate':
            model == null
                ? {
                  'available': false,
                  'reason':
                      'faltan las anclas plasma_scene y synthwave_scene en el harness',
                }
                : {
                  'available': true,
                  'anchors': _deviceAnchors,
                  'canvasEfficiencyCorePercent': _canvasEfficiencyCorePercent,
                  'gpuMsPerFrame': {'a': model.gpu.$1, 'b': model.gpu.$2},
                  'efficiencyCorePer10Fps': {
                    'a': model.efficiency.$1,
                    'b': model.efficiency.$2,
                  },
                  'renderThreadPer10Fps': {
                    'a': model.render.$1,
                    'b': model.render.$2,
                  },
                  'mostFavourableRatio':
                      contract?.mostFavourableRatio ??
                      _fallbackMostFavourableRatio,
                },
        'counts': {
          for (final state in CreatorReadinessState.values)
            state.name: counts[state] ?? 0,
        },
        'evidence': evidenceFiles,
        'visuals': registry,
      }),
    );
    _writeText(
      _studioFile,
      _encode({
        'schemaVersion': 1,
        'generatedAt': now,
        'catalogCommit': commit,
        // The studio compares this against the build manifest it bundles: a
        // changed SDK, runtime, compiler, resource, check, surface or contract
        // invalidates every technical label, even when the vote revision is
        // untouched. An export without a stamp is "unknown" in the studio.
        'engine': {
          'buildHash': buildHash,
          'sdkHash': (engine['manifest'] as Map)['sdkHash'],
          'abi': (engine['manifest'] as Map)['abi'],
        },
        'visuals': export,
      }),
    );
    if (!_linksFile.existsSync()) {
      _writeText(
        _linksFile,
        _encode({'schemaVersion': 1, 'links': <Object>[]}),
      );
    }
    out.writeln('Registro: ${_registryFile.path}');
    out.writeln('Exportado a Studio: ${_studioFile.path}');
    _printCounts(registry, author: null);
    return 0;
  }

  /// Cards by visual from `cards import` (explicit file, or the default
  /// `readiness/device_cards.json` when it exists).
  Map<String, List<Map<String, Object?>>> _loadCards(File? explicit) {
    final file = explicit ?? _cardsFile;
    if (!file.existsSync()) {
      if (explicit != null) throw _ToolError('Faltan las fichas: ${file.path}');
      return const {};
    }
    final json = _readJsonObject(file, 'las fichas del dispositivo');
    final cards = json['cards'];
    if (json['schemaVersion'] != 1 || cards is! Map) {
      throw _ToolError(
        '${file.path} no es un archivo de fichas de cards import (schemaVersion 1, cards).',
      );
    }
    return {
      for (final entry in cards.entries)
        '${entry.key}': [
          for (final card
              in entry.value is List ? entry.value as List : const [])
            if (card is Map<String, Object?>) card,
        ],
    };
  }

  void _printCounts(Map<String, Object?> visuals, {String? author}) {
    final total = <String, int>{};
    final mine = <String, int>{};
    var authored = 0;
    for (final value in visuals.values) {
      final entry = value as Map;
      final state = entry['state'] as String;
      total[state] = (total[state] ?? 0) + 1;
      final origin = entry['origin'];
      if (author != null && origin is Map && origin['author'] == author) {
        authored++;
        mine[state] = (mine[state] ?? 0) + 1;
      }
    }
    out.writeln('Total ${visuals.length}: ${_countsLine(total)}');
    if (author != null)
      out.writeln('$author ($authored): ${_countsLine(mine)}');
  }

  String _countsLine(Map<String, int> counts) => [
    for (final state in CreatorReadinessState.values)
      if (counts[state.name] != null) '${state.name} ${counts[state.name]}',
  ].join(', ');

  // --- status ---------------------------------------------------------------

  int status({required bool json, String? author}) {
    final registry = _readJsonObject(_registryFile, 'el registro técnico');
    final entries = registry['visuals'] as Map<String, Object?>? ?? {};
    final visuals = _definitions();
    final current = {for (final v in visuals) v.id: visualRevision(v)};
    final engine = _engine(visuals);
    final registryEngine = registry['engine'];
    final sameEngine =
        registryEngine is Map &&
        registryEngine['buildHash'] == engine['buildHash'];
    if (engine['bundledManifestMatches'] != true) {
      out.writeln(
        'AVISO: el manifiesto de build empaquetado no es el de este motor: '
        'ejecuta dart run tool/compile_visuals.dart.',
      );
    }
    if (!_contractFile.existsSync()) {
      out.writeln(
        'AVISO: sin copia del contrato de energía (contract import).',
      );
    }
    final rows = <Map<String, Object?>>[];
    var stale = 0;
    for (final visual in visuals) {
      final entry = entries[visual.id] as Map<String, Object?>?;
      var state = entry == null ? 'unknown' : entry['state'] as String;
      var detail =
          entry == null ? 'sin registro' : entry['detail'] as String? ?? '';
      if (entry != null && entry['revision'] != current[visual.id]) {
        state = 'unknown';
        detail =
            'el dibujo cambió desde la comprobación (${entry['revision']} → ${current[visual.id]})';
        stale++;
      } else if (entry != null && !sameEngine) {
        state = 'unknown';
        detail =
            'cambió el motor (manifiesto de build ${registryEngine is Map ? registryEngine['buildHash'] : 'sin sello'} → ${engine['buildHash']}): repite prepare';
        stale++;
      }
      rows.add({
        'id': visual.id,
        'kind': visual.isNative ? 'native' : 'shader',
        'fps': visual.framesPerSecond,
        'role': visual.role.name,
        'author':
            entry?['origin'] is Map ? (entry!['origin'] as Map)['author'] : '',
        'state': state,
        'detail': detail,
        'macVerdict': _macVerdict(entry),
      });
    }
    final missing = [
      for (final id in entries.keys)
        if (!current.containsKey(id)) id,
    ];
    if (json) {
      out.writeln(
        jsonEncode({
          'generatedAt': registry['generatedAt'],
          'catalogCommit': registry['catalogCommit'],
          'sameEngine': sameEngine,
          'stale': stale,
          'removed': missing,
          'visuals': rows,
        }),
      );
      return 0;
    }
    out.writeln(
      'Registro del ${registry['generatedAt']} (${registry['catalogCommit']}); motor ${sameEngine ? 'igual' : 'DISTINTO'}.',
    );
    for (final row in rows) {
      if (author != null && row['author'] != author) continue;
      out.writeln('${row['id']}: ${row['state']} · ${row['detail']}');
    }
    final counts = <String, int>{};
    final mine = <String, int>{};
    var authored = 0;
    for (final row in rows) {
      counts[row['state'] as String] =
          (counts[row['state'] as String] ?? 0) + 1;
      if (author != null && row['author'] == author) {
        authored++;
        mine[row['state'] as String] = (mine[row['state'] as String] ?? 0) + 1;
      }
    }
    out.writeln(
      'Total ${rows.length}: ${_countsLine(counts)}${stale > 0 ? ' (cambiados desde la comprobación: $stale)' : ''}',
    );
    if (author != null)
      out.writeln('$author ($authored): ${_countsLine(mine)}');
    if (missing.isNotEmpty)
      out.writeln('Ya no están en el catálogo: ${missing.join(', ')}');
    return stale > 0 || !sameEngine ? 1 : 0;
  }

  static Object? _macVerdict(Map<String, Object?>? entry) {
    final checks = entry?['checks'];
    if (checks is! Map) return null;
    final host = checks['hostCost'];
    return host is Map ? host['verdict'] : null;
  }

  // --- links ----------------------------------------------------------------

  List<Map<String, Object?>> _loadLinks() {
    if (!_linksFile.existsSync()) return [];
    final json = _readJsonObject(_linksFile, 'los enlaces de revisión');
    final items = json['links'];
    return [
      for (final item in items is List ? items : const [])
        if (item is Map<String, Object?>) item,
    ];
  }

  void _saveLinks(List<Map<String, Object?>> links) {
    links.sort(
      (a, b) =>
          '${a['visualId']}${a['to']}'.compareTo('${b['visualId']}${b['to']}'),
    );
    _writeText(_linksFile, _encode({'schemaVersion': 1, 'links': links}));
  }

  int linksStatus() {
    final links = _loadLinks();
    final counts = <String, int>{};
    for (final link in links) {
      final status = '${link['status']}';
      counts[status] = (counts[status] ?? 0) + 1;
      out.writeln(
        '${link['visualId']}: ${link['from']} → ${link['to']} · $status · ${link['kind']} · ${link['summary']}',
      );
    }
    out.writeln(
      'Enlaces ${links.length}: ${counts.entries.map((e) => '${e.key} ${e.value}').join(', ')}',
    );
    return 0;
  }

  /// Propone enlaces entre la revisión de [base] y la actual con evidencia
  /// automática; nunca marca uno como revisado.
  int linksPropose(String base, {String? captures}) {
    final current = {for (final v in _definitions()) v.id: v};
    final baseVisuals = _definitionsAt(base);
    final registry =
        _registryFile.existsSync()
            ? _readJsonObject(_registryFile, 'el registro')
            : null;
    final registryVisuals =
        registry?['visuals'] is Map
            ? registry!['visuals'] as Map<String, Object?>
            : <String, Object?>{};
    final links = _loadLinks();
    final now = DateTime.now().toUtc().toIso8601String();
    var proposed = 0, same = 0, rejectedByEvidence = 0;
    final noEvidence = <String>[];
    for (final entry in current.entries) {
      final id = entry.key, visual = entry.value;
      final old = baseVisuals[id];
      if (old == null) continue;
      final from = visualRevision(old), to = visualRevision(visual);
      if (from == to) {
        same++;
        continue;
      }
      final changed = _changedFields(old, visual);
      final registryEntry = registryVisuals[id] as Map<String, Object?>?;
      final checks = registryEntry?['checks'] as Map<String, Object?>?;
      String? replayStatus =
          (checks?['nativeReplay'] as Map?)?['status'] as String?;
      Map<String, Object?>? proposal;
      if (changed.length == 1 && changed.single == 'framesPerSecond') {
        final temporal = replayStatus == 'pass';
        proposal = {
          'kind': 'fpsOnly',
          'status': 'proposed',
          'summary':
              'Mismo programa, materiales, imágenes y parámetros; sólo cambia la cadencia '
              '${old.framesPerSecond} → ${visual.framesPerSecond} fps. '
              '${temporal ? 'La regla 30/60 de la revisión nativa pasa: el mismo dibujo en los mismos instantes.' : 'Sin registro técnico de esta revisión: ejecuta prepare.'} '
              'La suavidad del movimiento sí cambia: observar A/B antes de revisar.',
          'evidence': {
            'changedFields': changed,
            'temporalRule30_60': replayStatus ?? 'notRun',
            'registryRevision': registryEntry?['revision'],
          },
        };
      } else if (captures != null) {
        final parity = _pixelParity(Directory(captures), id);
        if (parity == null) {
          noEvidence.add(id);
        } else if (parity['equivalent'] == true) {
          proposal = {
            'kind': 'pixelParity',
            'status': 'proposed',
            'summary':
                'Cambió ${changed.join(', ')}; ${parity['frames']} capturas Metal en los mismos instantes '
                '(música fuerte y silencio) coinciden: diferencia máxima ${parity['maxDifference']}/255 en '
                '${parity['differentPercent']}% de píxeles. Alcance: valores iniciales. Observar A/B antes de revisar.',
            'evidence': {
              'changedFields': changed,
              'pixelParity': parity,
              'temporalRule30_60': replayStatus ?? 'notRun',
            },
          };
        } else {
          rejectedByEvidence++;
          proposal = {
            'kind': 'visibleChange',
            'status': 'rejected',
            'reviewer': 'readiness (evidencia automática)',
            'reviewedAt': now,
            'summary':
                'Cambió ${changed.join(', ')} y las capturas difieren: máximo ${parity['maxDifference']}/255 en '
                '${parity['differentPercent']}% de píxeles. Cambio real: se vuelve a votar.',
            'evidence': {'changedFields': changed, 'pixelParity': parity},
          };
        }
      } else {
        noEvidence.add(id);
      }
      if (proposal == null) continue;
      // Un enlace revisado o rechazado por una persona nunca se reemplaza.
      final existing = links.indexWhere(
        (l) => l['visualId'] == id && l['from'] == from && l['to'] == to,
      );
      if (existing >= 0) {
        final status = links[existing]['status'];
        final human =
            links[existing]['reviewer'] is String &&
            !'${links[existing]['reviewer']}'.startsWith('readiness');
        if ((status == 'reviewed' || status == 'rejected') && human) continue;
        links.removeAt(existing);
      }
      links.add({
        'visualId': id,
        'from': from,
        'to': to,
        'base': base,
        'proposedAt': now,
        ...proposal,
      });
      if (proposal['status'] == 'proposed') proposed++;
    }
    _saveLinks(links);
    out.writeln(
      'Base $base: iguales $same, propuestos $proposed, rechazados por evidencia $rejectedByEvidence, '
      'sin evidencia ${noEvidence.length}. Archivo: ${_linksFile.path}',
    );
    if (noEvidence.isNotEmpty) {
      out.writeln(
        'Sin evidencia (cambió el código: faltan capturas base/actual en los '
        'mismos instantes): ${noEvidence.join(', ')}',
      );
    }
    return 0;
  }

  Map<String, CreatorVisualDefinition> _definitionsAt(String ref) {
    final runtime = _git([
      'show',
      '$ref:packages/visual_catalog/assets/creator_catalog.json',
    ]);
    final metadata = _git([
      'show',
      '$ref:packages/visual_catalog/assets/catalog_metadata.json',
    ]);
    try {
      return {
        for (final v in decodeCreatorCatalog(
          runtimeJson: runtime,
          metadataJson: metadata,
        ))
          v.id: v,
      };
    } on Object catch (error) {
      throw _ToolError('El catálogo de $ref no se pudo leer: $error');
    }
  }

  static List<String> _changedFields(
    CreatorVisualDefinition a,
    CreatorVisualDefinition b,
  ) {
    Map<String, Object?> fields(CreatorVisualDefinition v) => {
      'nativeSource': v.nativeSource,
      'shaderSource': v.shaderSource,
      'shaderSources': v.shaderSources,
      'images': v.images,
      'imageHashes': v.nativeBuild['imageHashes'],
      'role': v.role.name,
      'reactivity': v.reactivity.name,
      'framesPerSecond': v.framesPerSecond,
      'seed': v.seed,
      'colors': v.colors,
      'controls': v.controls.toMap(),
      'modifiers': [
        for (final m in v.modifiers)
          {...m.toMap()}
            ..remove('label')
            ..remove('options'),
      ],
    };
    final fa = fields(a), fb = fields(b);
    return [
      for (final key in fa.keys)
        if (_canonicalJson(fa[key]) != _canonicalJson(fb[key])) key,
    ];
  }

  /// Compara `<captures>/base/<id>_t*.png` con `<captures>/current/<id>_t*.png`.
  Map<String, Object?>? _pixelParity(Directory captures, String id) {
    final base = Directory('${captures.path}/base'),
        current = Directory('${captures.path}/current');
    if (!base.existsSync() || !current.existsSync()) return null;
    // `<id>_t<ms>.png` as the harness writes it, or `<id>_t<ms>_<mode>.png`
    // when captures of several signal modes share one folder.
    final pattern = RegExp('^${RegExp.escape(id)}_t(\\d+)(?:_[a-z]+)?\\.png\$');
    final frames = <String>[];
    for (final file in base.listSync(followLinks: false).whereType<File>()) {
      final name = file.uri.pathSegments.last;
      if (pattern.hasMatch(name) && File('${current.path}/$name').existsSync())
        frames.add(name);
    }
    if (frames.isEmpty) return null;
    frames.sort();
    var maxDifference = 0;
    var different = 0, pixels = 0;
    for (final name in frames) {
      final a = _Png.decode(File('${base.path}/$name').readAsBytesSync());
      final b = _Png.decode(File('${current.path}/$name').readAsBytesSync());
      if (a.width != b.width || a.height != b.height) {
        return {
          'equivalent': false,
          'frames': frames.length,
          'reason': 'tamaños distintos en $name',
        };
      }
      for (var i = 0; i < a.rgba.length; i += 4) {
        var pixelMax = 0;
        for (var c = 0; c < 4; c++) {
          pixelMax = math.max(pixelMax, (a.rgba[i + c] - b.rgba[i + c]).abs());
        }
        if (pixelMax > 2) different++;
        maxDifference = math.max(maxDifference, pixelMax);
        pixels++;
      }
    }
    final percent = pixels == 0 ? 0.0 : different * 100 / pixels;
    return {
      'equivalent': maxDifference <= 2 || percent <= 0.1,
      'frames': frames.length,
      'instants': frames,
      'maxDifference': maxDifference,
      'differentPercent': double.parse(percent.toStringAsFixed(3)),
    };
  }

  int linksReview(
    String id, {
    required String from,
    required String to,
    required String reviewer,
    required bool reject,
    required String note,
  }) {
    final visuals = {for (final v in _definitions()) v.id: v};
    final visual = visuals[id];
    if (visual == null)
      throw _ToolError('No existe el visual $id en el catálogo.');
    final current = visualRevision(visual);
    if (to != current) {
      throw _ToolError(
        'La revisión actual de $id es $current, no $to: revisa lo que se ve ahora.',
      );
    }
    if (from == to || from.isEmpty || to.isEmpty) {
      throw const _ToolError(
        'Un enlace necesita dos revisiones distintas y no vacías.',
      );
    }
    final links = _loadLinks();
    final index = links.indexWhere(
      (l) => l['visualId'] == id && l['from'] == from && l['to'] == to,
    );
    if (index < 0) {
      throw _ToolError(
        'No hay una propuesta $from → $to para $id. Ejecuta links propose primero.',
      );
    }
    if (reviewer.trim().isEmpty || reviewer.startsWith('readiness')) {
      throw const _ToolError('Indica el nombre de quien revisó el A/B.');
    }
    final proposal = links[index];
    // Only a proposal can be reviewed: an evidence-rejected link (a visible
    // difference) is not force-approved; re-propose or re-vote instead.
    if (proposal['status'] != 'proposed') {
      throw _ToolError(
        'El enlace $from → $to de $id está en estado ${proposal['status']}, '
        'no «proposed»: no se puede revisar.',
      );
    }
    // Approving requires real evidence and provenance; rejecting never does.
    if (!reject) {
      final evidence = proposal['evidence'];
      if (evidence is! Map || evidence.isEmpty) {
        throw _ToolError(
          'La propuesta $from → $to de $id no tiene evidencia (capturas o la '
          'regla 30/60): ejecuta links propose con --captures antes de revisar.',
        );
      }
      // No cycles: a reviewed reverse link would make votes flow both ways.
      final reverse = links.any(
        (l) =>
            l['visualId'] == id &&
            l['from'] == to &&
            l['to'] == from &&
            l['status'] == 'reviewed',
      );
      if (reverse) {
        throw _ToolError(
          'Ya hay un enlace revisado $to → $from para $id: revisarlo al revés '
          'crearía un ciclo.',
        );
      }
    }
    links[index] = {
      ...proposal,
      'status': reject ? 'rejected' : 'reviewed',
      'reviewer': reviewer.trim(),
      'reviewedAt': DateTime.now().toUtc().toIso8601String(),
      'note': note,
    };
    _saveLinks(links);
    out.writeln(
      '$id: $from → $to ${reject ? 'rechazado' : 'revisado'} por $reviewer.',
    );
    return 0;
  }
}

/// PNG de 8 bits (gris, gris+alpha, RGB, RGBA), sin entrelazado: lo que
/// escribe el harness. Devuelve RGBA.
class _Png {
  _Png(this.width, this.height, this.rgba);

  final int width, height;
  final List<int> rgba;

  static _Png decode(List<int> bytes) {
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    for (var i = 0; i < 8; i++) {
      if (bytes[i] != signature[i]) throw const _ToolError('No es un PNG.');
    }
    var pos = 8;
    int? width, height, colorType, depth, interlace;
    final data = <int>[];
    while (pos + 8 <= bytes.length) {
      final length = _u32(bytes, pos);
      final type = String.fromCharCodes(bytes.sublist(pos + 4, pos + 8));
      final start = pos + 8;
      if (type == 'IHDR') {
        width = _u32(bytes, start);
        height = _u32(bytes, start + 4);
        depth = bytes[start + 8];
        colorType = bytes[start + 9];
        interlace = bytes[start + 12];
      } else if (type == 'IDAT') {
        data.addAll(bytes.sublist(start, start + length));
      } else if (type == 'IEND') {
        break;
      }
      pos = start + length + 4;
    }
    if (width == null || height == null || depth != 8 || interlace != 0) {
      throw const _ToolError('PNG no admitido (sólo 8 bits sin entrelazado).');
    }
    final channels = switch (colorType) {
      0 => 1,
      2 => 3,
      4 => 2,
      6 => 4,
      _ => throw const _ToolError('PNG con paleta no admitido.'),
    };
    final raw = zlib.decode(data);
    final stride = width * channels;
    final out = List<int>.filled(width * height * 4, 255);
    var previous = List<int>.filled(stride, 0);
    var offset = 0;
    for (var y = 0; y < height; y++) {
      final filter = raw[offset++];
      final line = List<int>.from(raw.sublist(offset, offset + stride));
      offset += stride;
      for (var x = 0; x < stride; x++) {
        final a = x >= channels ? line[x - channels] : 0;
        final b = previous[x];
        final c = x >= channels ? previous[x - channels] : 0;
        line[x] =
            switch (filter) {
              0 => line[x],
              1 => line[x] + a,
              2 => line[x] + b,
              3 => line[x] + ((a + b) >> 1),
              4 => line[x] + _paeth(a, b, c),
              _ => throw const _ToolError('Filtro PNG desconocido.'),
            } &
            0xff;
      }
      for (var x = 0; x < width; x++) {
        final o = (y * width + x) * 4, i = x * channels;
        switch (channels) {
          case 1:
            out[o] = out[o + 1] = out[o + 2] = line[i];
          case 2:
            out[o] = out[o + 1] = out[o + 2] = line[i];
            out[o + 3] = line[i + 1];
          case 3:
            out[o] = line[i];
            out[o + 1] = line[i + 1];
            out[o + 2] = line[i + 2];
          default:
            out[o] = line[i];
            out[o + 1] = line[i + 1];
            out[o + 2] = line[i + 2];
            out[o + 3] = line[i + 3];
        }
      }
      previous = line;
    }
    return _Png(width, height, out);
  }

  static int _u32(List<int> b, int i) =>
      (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];

  static int _paeth(int a, int b, int c) {
    final p = a + b - c;
    final pa = (p - a).abs(), pb = (p - b).abs(), pc = (p - c).abs();
    if (pa <= pb && pa <= pc) return a;
    return pb <= pc ? b : c;
  }
}
