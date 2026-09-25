import 'dart:io';

Future<void> main() async {
  final creator = File.fromUri(Platform.script).parent.parent;
  final audiovisual = creator.parent;
  final compile = await Process.run(Platform.resolvedExecutable, [
    'run',
    'tool/compile_visuals.dart',
  ], workingDirectory: creator.path);
  if (compile.exitCode != 0) {
    stderr.write(compile.stderr);
    exitCode = compile.exitCode;
    return;
  }
  final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
    RegExp(r'[^0-9]'),
    '',
  );
  final export = Directory('${audiovisual.path}/dist/visual-creator-$stamp')
    ..createSync(recursive: true);
  _copyTree(creator, Directory('${export.path}/studio'));
  for (final name in [
    'scene_compositor',
    'scene_compositor_host',
    'scene_program_native',
    'visual_contract',
    'visual_catalog',
  ]) {
    _copyTree(
      Directory('${audiovisual.path}/packages/$name'),
      Directory('${export.path}/packages/$name'),
    );
  }
  _copyTree(
    Directory('${audiovisual.path}/templates'),
    Directory('${export.path}/templates'),
  );
  for (final name in ['README.md', 'MAINTAINER.md', 'VERIFICATION.md', 'AGENTS.md', '.gitignore']) {
    final file = File('${audiovisual.path}/$name');
    if (file.existsSync()) file.copySync('${export.path}/$name');
  }
  File('${export.path}/LEEME.txt').writeAsStringSync(
    'Abre studio en tu IDE Flutter. Lee studio/README.md.\n'
    'Copia ambas plantillas a packages/visual_catalog/lib/visuals/: mi_visual.dart y mi_visual_metadata.dart.\n'
    'Conserva packages y templates al lado de studio.\n',
  );
  final archive = '${export.path}.zip';
  final result = await Process.run('zip', [
    '-q',
    '-r',
    archive,
    export.uri.pathSegments.where((s) => s.isNotEmpty).last,
  ], workingDirectory: export.parent.path);
  if (result.exitCode != 0) {
    stderr.write(result.stderr);
    exitCode = result.exitCode;
    return;
  }
  stdout.writeln(archive);
}

const _excludedDirectories = {
  '.git',
  '.dart_tool',
  'build',
  'Pods',
  '.symlinks',
  'ephemeral',
  '.idea',
  '.gradle',
  '.cxx',
  '.kotlin',
  'xcuserdata',
  '.swiftpm',
};
const _excludedFiles = {
  '.DS_Store',
  '.flutter-plugins-dependencies',
  '.flutter-plugins',
  'local.properties',
  'Generated.xcconfig',
  'flutter_export_environment.sh',
  '.last_build_id',
};

void _copyTree(Directory source, Directory target) {
  target.createSync(recursive: true);
  for (final item in source.listSync(followLinks: false)) {
    final name = item.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (_excludedDirectories.contains(name) ||
        _excludedFiles.contains(name) ||
        name.endsWith('.iml'))
      continue;
    if (item is Directory) {
      _copyTree(item, Directory('${target.path}/$name'));
    } else if (item is File) {
      item.copySync('${target.path}/$name');
    } else if (item is Link) {
      throw FileSystemException(
        'Un enlace impediría entregar un kit independiente',
        item.path,
      );
    }
  }
}
