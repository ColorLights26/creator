import 'dart:convert';
import 'dart:io';

import 'package:scene_compositor/authoring.dart';
import 'package:visual_contract/visual_contract.dart';

import 'package:visual_catalog/src/registry.g.dart';
import 'portable_shader.dart';

/// Second phase: the registry has already been regenerated before this library
/// is compiled. Studio receives the full authoring catalog; production builds
/// its own approved snapshots using the same wire format and shader compiler.
void main() {
  try {
    final root = File.fromUri(Platform.script).parent.parent;
    final catalogRoot = Directory(
      '${root.parent.path}/packages/visual_catalog',
    );
    final visuals = validateCreatorCatalog(creatorSourceVisuals);
    for (final visual in visuals) {
      final thumbnail = visual.thumbnail;
      final path = thumbnail.assetPath;
      if (path != null &&
          (thumbnail.assetPackage == null ||
              thumbnail.assetPackage == 'visual_catalog') &&
          !File('${catalogRoot.path}/$path').existsSync()) {
        throw FormatException('${visual.id}: no existe la miniatura $path.');
      }
    }
    _writeIfChanged(
      File('${catalogRoot.path}/assets/creator_catalog.json'),
      '${encodeCreatorCatalog(visuals)}\n',
    );
    _writeIfChanged(
      File('${catalogRoot.path}/shaders/creator_programs.frag'),
      compilePortableShader(visuals),
    );
    _writeIfChanged(
      File('${catalogRoot.path}/assets/catalog_metadata.json'),
      '${const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'visuals': [for (final visual in visuals) visual.toMetadata()],
      })}\n',
    );
    final recordings = <Map<String, Object>>[];
    final directory = Directory('${root.path}/recordings');
    if (directory.existsSync()) {
      final folders =
          directory.listSync().whereType<Directory>().toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      for (final folder in folders) {
        final signalsFile = File('${folder.path}/signals.bin');
        final timelineFile = File('${folder.path}/timeline.json');
        if (!signalsFile.existsSync() || !timelineFile.existsSync()) {
          throw FormatException(
            '${folder.path}: faltan signals.bin o timeline.json.',
          );
        }
        if (signalsFile.lengthSync() > 56 * 1024 * 1024 ||
            timelineFile.lengthSync() > 32 * 1024 * 1024) {
          throw FormatException('${folder.path}: grabación demasiado grande.');
        }
        final signals = signalsFile.readAsBytesSync();
        final timeline = timelineFile.readAsStringSync();
        final recording = SceneSignalRecording.fromBundle(
          signals: signals,
          timelineJson: timeline,
        );
        if (recording.qaSessionSeed > 0xffffffff) {
          throw FormatException(
            '${folder.path}: la semilla supera uint32; no se puede alterar.',
          );
        }
        recordings.add({
          'name': folder.uri.pathSegments.where((s) => s.isNotEmpty).last,
          'signalsBase64': base64Encode(signals),
          'timelineJson': timeline,
        });
      }
    }
    _writeIfChanged(
      File('${root.path}/assets/recordings.json'),
      '${jsonEncode(recordings)}\n',
    );
    stdout.writeln(
      'Visual Studio: ${visuals.length} visuales, ${recordings.length} grabaciones.',
    );
  } on Object catch (error) {
    stderr.writeln(
      'No se pudo compilar packages/visual_catalog/lib/visuals: $error',
    );
    exitCode = 1;
  }
}

void _writeIfChanged(File file, String contents) {
  if (file.existsSync() && file.readAsStringSync() == contents) return;
  file.parent.createSync(recursive: true);
  final temporary = File('${file.path}.${pid}.tmp');
  temporary.writeAsStringSync(contents, flush: true);
  temporary.renameSync(file.path);
}
