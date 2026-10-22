import 'dart:convert';
import 'dart:io';

import '../../packages/scene_compositor/lib/src/creator_source_admission.dart';
import '../lib/studio/visual_uploads.dart';

const studioUploadsAsset = 'studio/assets/visual_uploads.json';
const _hookMarker = '# Creator visual deliveries (managed)';

void main(List<String> arguments) {
  try {
    final Directory repo;
    if (arguments.isEmpty) {
      repo = File.fromUri(Platform.script).parent.parent.parent;
    } else if (arguments.length == 2 && arguments.first == '--repo') {
      repo = Directory(arguments[1]).absolute;
    } else {
      throw const FormatException(
        'Uso: generate_visual_collections.dart [--repo <creator>]',
      );
    }
    final uploads = writeStudioVisualUploads(
      repo,
      installHooks: true,
      generatorScript: File.fromUri(Platform.script),
    );
    stdout.writeln(
      'Entregas de Creator: ${uploads.length} visuales registrados.',
    );
  } on Object catch (error) {
    stderr.writeln('No se pudieron preparar las entregas: $error');
    exitCode = 1;
  }
}

List<StudioVisualUpload> writeStudioVisualUploads(
  Directory repo, {
  bool installHooks = false,
  File? generatorScript,
  String? dartExecutable,
}) {
  final target = File('${repo.path}/$studioUploadsAsset');
  final previous = {
    if (target.existsSync())
      for (final upload in decodeStudioVisualUploads(target.readAsStringSync()))
        upload.visualId: upload,
  };
  final introductions = _gitIntroductions(repo);
  final directory = Directory(
    '${repo.path}/packages/visual_catalog/lib/visuals',
  );
  final files =
      directory
          .listSync(followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('_metadata.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final uploads = <StudioVisualUpload>[];
  final ids = <String>{};
  for (final file in files) {
    final id = _metadataId(file.readAsStringSync());
    if (!ids.add(id)) throw FormatException('ID de visual repetido: $id.');
    final companion = File(
      file.path.replaceFirst(RegExp(r'_metadata\.dart$'), '.dart'),
    );
    if (!companion.existsSync()) {
      throw FormatException('Falta el compañero de ${file.path}.');
    }
    final relative = file.path
        .substring(repo.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    final origin = introductions[relative];
    // A stable ID keeps its original delivery if its files are renamed.
    final cached = previous[id];
    final StudioVisualUpload upload;
    if (cached?.date != null &&
        (origin == null || cached!.date!.compareTo(origin.date!) <= 0)) {
      upload = cached!;
    } else if (origin != null) {
      upload = StudioVisualUpload(
        visualId: id,
        author: origin.author,
        date: origin.date,
      );
    } else {
      // Exports have no Git history. Keep their bundled provenance; new
      // uncommitted pairs remain visible without inventing a delivery date.
      upload = cached ?? StudioVisualUpload(visualId: id);
    }
    uploads.add(upload);
  }
  uploads.sort((a, b) => a.visualId.compareTo(b.visualId));
  final contents = encodeStudioVisualUploads(uploads);
  if (!target.existsSync() || target.readAsStringSync() != contents) {
    target.parent.createSync(recursive: true);
    final temporary = File('${target.path}.$pid.tmp');
    temporary.writeAsStringSync(contents, flush: true);
    temporary.renameSync(target.path);
  }
  if (installHooks && _isRepository(repo)) {
    installStudioUploadHooks(
      repo,
      generatorScript ??
          File('${repo.path}/studio/tool/generate_visual_collections.dart'),
      dartExecutable: dartExecutable,
    );
  }
  return uploads;
}

ProcessResult _git(Directory repo, List<String> arguments) => Process.runSync(
  'git',
  ['-C', repo.path, ...arguments],
  stdoutEncoding: utf8,
  stderrEncoding: utf8,
);

bool _isRepository(Directory repo) {
  try {
    final result = _git(repo, ['rev-parse', '--show-toplevel']);
    return result.exitCode == 0 &&
        Directory(
              (result.stdout as String).trim(),
            ).resolveSymbolicLinksSync() ==
            repo.resolveSymbolicLinksSync();
  } on ProcessException {
    return false;
  }
}

Map<String, StudioVisualUpload> _gitIntroductions(Directory repo) {
  if (!_isRepository(repo)) return {};
  if (_git(repo, ['rev-parse', '--verify', 'HEAD']).exitCode != 0) return {};
  final shallow = _git(repo, ['rev-parse', '--is-shallow-repository']);
  if (shallow.exitCode != 0) throw StateError(shallow.stderr.toString());
  // A shallow boundary looks like every file was created together. Prefer
  // the portable snapshot instead of assigning false dates.
  if ((shallow.stdout as String).trim() == 'true') return {};
  final result = _git(repo, [
    'log',
    '--reverse',
    '--diff-filter=A',
    '--no-renames',
    '--format=CREATOR_UPLOAD%x00%aI%x00%an',
    '--name-only',
    '--',
    'packages/visual_catalog/lib/visuals/*_metadata.dart',
  ]);
  if (result.exitCode != 0) throw StateError(result.stderr.toString());
  final origins = <String, StudioVisualUpload>{};
  String? author;
  String? date;
  for (final line in const LineSplitter().convert(result.stdout as String)) {
    if (line.startsWith('CREATOR_UPLOAD\u0000')) {
      final fields = line.split('\u0000');
      if (fields.length != 3 || fields[1].length < 10) {
        throw const FormatException('Cabecera de entrega Git inválida.');
      }
      date = fields[1].substring(0, 10);
      author = fields[2].trim();
      if (!isStudioUploadDate(date) || author.isEmpty) {
        throw const FormatException('Autor o fecha Git inválidos.');
      }
    } else if (line.startsWith('packages/') && author != null && date != null) {
      origins.putIfAbsent(
        line,
        () => StudioVisualUpload(visualId: '', author: author, date: date),
      );
    }
  }
  return origins;
}

String _metadataId(String source) {
  validateCreatorMetadataSource(source);
  final code = stripComments(source);
  final tokens =
      RegExp(
        r'''r?"""[\s\S]*?"""|r?'{3}[\s\S]*?'{3}|r?"(?:\\.|[^"\\])*"|r?'(?:\\.|[^'\\])*'|[A-Za-z_][A-Za-z_0-9]*|[^\s]''',
      ).allMatches(code).map((match) => match.group(0)!).toList();
  var depth = 0;
  for (
    var i = tokens.indexOf('CreatorVisualMetadata') + 1;
    i < tokens.length;
    i++
  ) {
    final token = tokens[i];
    if (token == '(' || token == '[' || token == '{') depth++;
    if (token == ')' || token == ']' || token == '}') depth--;
    if (depth == 1 &&
        token == 'id' &&
        i + 2 < tokens.length &&
        tokens[i + 1] == ':') {
      final value = tokens[i + 2].replaceFirst(RegExp(r'^r'), '');
      if (value.length >= 3 &&
          (value.startsWith("'") || value.startsWith('"')) &&
          value.endsWith(value[0])) {
        final id = value.substring(1, value.length - 1);
        if (RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(id)) return id;
      }
      throw const FormatException('El ID debe ser un literal en snake_case.');
    }
  }
  throw const FormatException('Falta el ID en la metadata del visual.');
}

void installStudioUploadHooks(
  Directory repo,
  File generatorScript, {
  String? dartExecutable,
}) {
  for (final name in ['post-merge', 'post-checkout', 'post-rewrite']) {
    final result = _git(repo, ['rev-parse', '--git-path', 'hooks/$name']);
    if (result.exitCode != 0) throw StateError(result.stderr.toString());
    final path = (result.stdout as String).trim();
    final hook = File(path.startsWith('/') ? path : '${repo.path}/$path');
    if (hook.existsSync() && !hook.readAsStringSync().contains(_hookMarker)) {
      stderr.writeln('Se conserva el hook existente: ${hook.path}.');
      continue;
    }
    final contents =
        '#!/bin/sh\n$_hookMarker\nset -eu\n'
        'creator_root=\$(git rev-parse --show-toplevel)\n'
        'exec ${_shellQuote(dartExecutable ?? Platform.resolvedExecutable)} '
        '${_shellQuote(generatorScript.absolute.path)} --repo "\$creator_root"\n';
    hook.parent.createSync(recursive: true);
    if (!hook.existsSync() || hook.readAsStringSync() != contents) {
      hook.writeAsStringSync(contents, flush: true);
      if (!Platform.isWindows) {
        final chmod = Process.runSync('chmod', ['+x', hook.path]);
        if (chmod.exitCode != 0) throw StateError(chmod.stderr.toString());
      }
    }
  }
}

String _shellQuote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";
