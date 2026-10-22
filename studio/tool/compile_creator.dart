import 'dart:io';

import 'compile_visuals.dart' as catalog;
import 'generate_visual_collections.dart';

void main(List<String> args) {
  catalog.main(args);
  if (exitCode != 0) return;
  try {
    writeStudioVisualUploads(
      File.fromUri(Platform.script).parent.parent.parent,
      installHooks: true,
    );
  } on Object catch (error) {
    stderr.writeln('No se pudieron preparar las entregas: $error');
    exitCode = 1;
  }
}
