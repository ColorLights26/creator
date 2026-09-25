import 'dart:io';

/// Bootstrap discovery before importing any generated library. Dart cannot
/// discover new source files at runtime; this runs before the application build.
void main(List<String> arguments) {
  try {
    final studio = File.fromUri(Platform.script).parent.parent;
    final catalog = Directory('${studio.parent.path}/packages/visual_catalog');
    writeCreatorRegistry(catalog);
    if (arguments.isNotEmpty &&
        (arguments.length != 2 || arguments.first != '--package-config')) {
      throw const FormatException(
        'Uso: compile_visuals.dart [--package-config <ruta>]',
      );
    }
    final packageConfig =
        File(
          arguments.isEmpty
              ? '${studio.path}/.dart_tool/package_config.json'
              : arguments[1],
        ).absolute;
    if (!packageConfig.existsSync()) {
      throw const FormatException('Ejecuta flutter pub get en studio primero.');
    }
    final result = Process.runSync(Platform.resolvedExecutable, [
      '--packages=${packageConfig.path}',
      '${studio.path}/tool/build_catalog_assets.dart',
    ], workingDirectory: studio.path);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    exitCode = result.exitCode;
  } on Object catch (error) {
    stderr.writeln('No se pudo preparar el catálogo: $error');
    exitCode = 1;
  }
}

/// Stable ordering keeps shader indices identical across the app and the studio.
String generateCreatorRegistry(Directory visualsDirectory) {
  if (!visualsDirectory.existsSync()) {
    throw FormatException('No existe ${visualsDirectory.path}.');
  }
  final names = <String>[];
  for (final entity in visualsDirectory.listSync(followLinks: false)) {
    if (!entity.path.endsWith('.dart')) continue;
    if (entity is! File) {
      throw FormatException(
        'Usa archivos Dart locales, no enlaces: ${entity.path}',
      );
    }
    final name = entity.uri.pathSegments.last;
    if (!RegExp(r'^[a-z][a-z0-9_]*\.dart$').hasMatch(name)) {
      throw FormatException('$name: usa un nombre de archivo en snake_case.');
    }
    if (entity.lengthSync() > 256 * 1024) {
      throw FormatException('$name supera el tamaño permitido.');
    }
    names.add(name);
  }
  names.sort();
  if (names.isEmpty || names.length > 64) {
    throw const FormatException('Añade entre 1 y 64 archivos de visuales.');
  }
  return '''// Generated from lib/visuals/*.dart. Do not edit.
import 'package:scene_compositor/authoring.dart';
${[for (var i = 0; i < names.length; i++) "import '../visuals/${names[i]}' as visual_$i;"].join('\n')}

const creatorSourceVisuals = <CreatorVisualDefinition>[
${[for (var i = 0; i < names.length; i++) '  visual_$i.visual,'].join('\n')}
];
''';
}

void writeCreatorRegistry(Directory catalog) {
  final source = generateCreatorRegistry(
    Directory('${catalog.path}/lib/visuals'),
  );
  final target = File('${catalog.path}/lib/src/registry.g.dart');
  if (target.existsSync() && target.readAsStringSync() == source) return;
  target.parent.createSync(recursive: true);
  final temporary = File('${target.path}.${pid}.tmp');
  temporary.writeAsStringSync(source, flush: true);
  temporary.renameSync(target.path);
}
