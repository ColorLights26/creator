/// Build-time only. Never imported by the application runtime.
library;

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'authoring.dart';

String _hash(List<int> bytes) => sha256.convert(bytes).toString();
void writeCreatorFile(File target, List<int> bytes) {
  if (target.existsSync() && _hash(target.readAsBytesSync()) == _hash(bytes))
    return;
  target.parent.createSync(recursive: true);
  final temporary = File('${target.path}.$pid.tmp')
    ..writeAsBytesSync(bytes, flush: true);
  temporary.renameSync(target.path);
}

Directory creatorNativeSdk(Directory host) {
  final configFile = File('${host.path}/.dart_tool/package_config.json');
  final config = jsonDecode(configFile.readAsStringSync()) as Map;
  final package = (config['packages'] as List).cast<Map>().singleWhere(
    (p) => p['name'] == 'scene_program_native',
  );
  return Directory.fromUri(
    configFile.uri.resolve(package['rootUri'] as String),
  );
}

String creatorNativeSdkHash(Directory host) {
  final sdk = creatorNativeSdk(host);
  final sdkFiles = [
    'creator_abi.h',
    '../ios/Classes/creator_abi.h',
    'creator_scene.hpp',
    'creator_scene.cpp',
    'creator_registry.cpp',
  ];
  final sdkHash = _hash(
    utf8.encode(
      sdkFiles
          .map((f) => File('${sdk.path}/src/$f').readAsStringSync())
          .join('\n'),
    ),
  );
  return sdkHash;
}

Directory creatorNativeOutput(Directory host) {
  final configuration = Platform.environment['CREATOR_NATIVE_CONFIGURATION'];
  if (configuration == null || configuration.isEmpty) {
    return Directory('${host.path}/build/creator_native');
  }
  if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(configuration)) {
    throw const FormatException('Invalid native build configuration.');
  }
  return Directory('${host.path}/build/creator_native/$configuration');
}

/// Must run under the host's preparation lock, before native and Flutter builds.
/// Includes belong to the host build tree, never to the shared SDK checkout.
Map<String, Object> prepareCreatorNative({
  required Directory host,
  required Directory catalog,
  required List<CreatorVisualDefinition> visuals,
  Directory? outputDirectory,
}) {
  final output = outputDirectory ?? creatorNativeOutput(host);
  output.createSync(recursive: true);
  final sdkHash = creatorNativeSdkHash(host);
  final manifests = <Map<String, Object>>[];
  final declarations = StringBuffer(
    '// Generated. All programs compiled into this host.\n',
  );
  final entries = <String>[];
  for (final visual in visuals) {
    final manifest = visual.toManifest();
    if (!visual.isNative) {
      manifests.add(manifest);
      continue;
    }
    final materials = visual.shaderSources.keys.toList()..sort();
    final images = visual.images.keys.toList()..sort();
    final imageHashes = <String, String>{};
    for (final name in images) {
      final path = File('${catalog.path}/${visual.images[name]}');
      if (!path.existsSync() || path.lengthSync() > 16 * 1024 * 1024)
        throw FormatException(
          '${visual.id}: imagen inexistente o mayor de 16 MiB: ${visual.images[name]}',
        );
      imageHashes[name] = _hash(path.readAsBytesSync());
    }
    final compiled = <String, Object>{};
    for (final name in materials) {
      compiled[name] = _compileMaterial(host, catalog, output, visual, name);
    }
    final hash = _hash(
      utf8.encode(
        jsonEncode([
          1,
          sdkHash,
          visual.nativeSource,
          for (final name in materials)
            [name, visual.shaderSources[name], compiled[name]],
          imageHashes,
        ]),
      ),
    );
    manifest['nativeBuild'] = {
      'abi': 1,
      'hash': hash,
      'sdkHash': sdkHash,
      'materials': compiled,
      'imageHashes': imageHashes,
    };
    manifests.add(manifest);
    // Common standard headers are loaded outside each isolated author namespace.
    declarations.writeln(
      'namespace authored_${visual.id} {\nusing namespace creator;',
    );
    declarations.writeln(
      '#line ${visual.sourceLine} ${jsonEncode(visual.sourceFile)}',
    );
    declarations.writeln(visual.nativeSource);
    declarations.writeln('#line 1 "creator_programs.inc"');
    declarations.writeln(
      'std::unique_ptr<creator::Scene> make() { return std::make_unique<Visual>(); }\n}',
    );
    entries.add(
      '{${jsonEncode(visual.programId)}, ${jsonEncode(hash)}, &authored_${visual.id}::make, {${materials.map(jsonEncode).join(',')}}, {${images.map(jsonEncode).join(',')}}}',
    );
  }
  declarations.writeln(
    'namespace creator { const std::vector<Program>& installedPrograms() {\nstatic const std::vector<Program> programs = {${entries.join(',\n')}};\nreturn programs;\n} }',
  );
  // Registry is committed only after every shader and resource passed preparation.
  writeCreatorFile(
    File('${output.path}/creator_programs.inc'),
    utf8.encode(declarations.toString()),
  );
  return {'schemaVersion': 1, 'visuals': manifests};
}

Map<String, Object> _compileMaterial(
  Directory host,
  Directory catalog,
  Directory output,
  CreatorVisualDefinition visual,
  String name,
) {
  final config = File('${host.path}/.dart_tool/package_config.json');
  final packages =
      (jsonDecode(config.readAsStringSync()) as Map)['packages'] as List;
  final flutterPackage = packages.cast<Map>().singleWhere(
    (p) => p['name'] == 'flutter',
  );
  final flutterRoot =
      Directory.fromUri(
        config.uri.resolve(flutterPackage['rootUri'] as String),
      ).parent.parent;
  final engine = Directory('${flutterRoot.path}/bin/cache/artifacts/engine');
  final candidates =
      engine
          .listSync()
          .whereType<Directory>()
          .where(
            (d) =>
                File(
                  '${d.path}/impellerc${Platform.isWindows ? '.exe' : ''}',
                ).existsSync(),
          )
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  if (candidates.isEmpty)
    throw StateError('Falta el compilador de shaders del SDK Flutter.');
  final compiler =
      '${candidates.first.path}/impellerc${Platform.isWindows ? '.exe' : ''}';
  final includes = '${candidates.first.path}/shader_lib';
  final basename = '${visual.id}_$name';
  final source = File('${output.path}/$basename.frag');
  final material = visual.shaderSources[name]!;
  var originalLine = 1;
  final authoredFile = File('${catalog.path}/lib/visuals/${visual.sourceFile}');
  if (authoredFile.existsSync()) {
    final authored = authoredFile.readAsStringSync();
    final offset = authored.indexOf(material);
    if (offset >= 0)
      originalLine = '\n'.allMatches(authored.substring(0, offset)).length + 1;
  }
  writeCreatorFile(source, utf8.encode(material));
  final digest = _hash([
    ...utf8.encode('material-abi-2-samplers\n$material'),
    ...File(compiler).readAsBytesSync(),
    ...File('$includes/flutter/runtime_effect.glsl').readAsBytesSync(),
  ]);
  final cache = File('${output.path}/$basename.compiled.json');
  final asset = 'assets/native/$basename.iplr';
  if (cache.existsSync() && File('${catalog.path}/$asset').existsSync()) {
    final previous =
        jsonDecode(cache.readAsStringSync()) as Map<String, dynamic>;
    if (previous['compilerHash'] == digest &&
        previous['assetHash'] ==
            _hash(File('${catalog.path}/$asset').readAsBytesSync()))
      return previous.cast<String, Object>();
  }
  void run(List<String> flags) {
    final result = Process.runSync(compiler, [
      ...flags,
      '--input=${source.path}',
      '--spirv=${output.path}/$basename.spirv',
      '--include=$includes',
    ]);
    if (result.exitCode != 0) {
      final diagnostic = '${result.stderr}\n${result.stdout}'.replaceAllMapped(
        RegExp('${RegExp.escape(source.path)}:(\\d+)'),
        (match) =>
            '${visual.sourceFile}:${int.parse(match[1]!) + originalLine - 1}',
      );
      throw FormatException(
        '${visual.sourceFile}:$originalLine: revisa el material $name.\n$diagnostic',
      );
    }
  }

  final metal = '${output.path}/$basename.metal';
  final reflection = '${output.path}/$basename.reflection.json';
  run([
    '--runtime-stage-metal',
    '--sl=$metal',
    '--reflection-json=$reflection',
  ]);
  final binary = '${output.path}/$basename.iplr';
  run([
    '--runtime-stage-metal',
    '--runtime-stage-gles',
    '--runtime-stage-gles3',
    '--runtime-stage-vulkan',
    '--sksl',
    '--iplr',
    '--sl=$binary',
  ]);
  final reflected =
      jsonDecode(File(reflection).readAsStringSync()) as Map<String, dynamic>;
  final uniforms =
      [
          ...(reflected['uniforms'] as List),
          ...(reflected['sampled_images'] as List),
        ].cast<Map<String, dynamic>>()
        ..sort(
          (a, b) => (a['location'] as int).compareTo(b['location'] as int),
        );
  var offset = 0;
  var sampler = 0;
  final fields = <Map<String, Object>>[];
  for (final uniform in uniforms) {
    final type = uniform['type'] as Map;
    final typename = type['type_name'] as String;
    if (typename.contains('SampledImage')) {
      fields.add({
        'name': uniform['name'],
        'sampler': sampler++,
        'textureIndex': uniform['ext_res_0'],
        'samplerIndex': uniform['ext_res_1'],
      });
    } else {
      final count = type['vec_size'] as int;
      if (typename != 'ShaderType::kFloat' ||
          type['columns'] != 1 ||
          count < 1 ||
          count > 4 ||
          (type['members'] as List).isNotEmpty)
        throw FormatException(
          '${visual.sourceFile}: $name usa un uniform no compatible: ${uniform['name']}. Usa float/vec2/vec3/vec4 y sampler2D.',
        );
      fields.add({
        'name': uniform['name'],
        'offset': offset,
        'count': count,
        'bufferIndex': uniform['ext_res_0'],
      });
      offset += count;
    }
  }
  if (fields.isEmpty ||
      fields.first['name'] != 'uSize' ||
      fields.first['count'] != 2)
    throw FormatException(
      '${visual.sourceFile}: $name debe empezar con uniform vec2 uSize.',
    );
  if (offset > 1026 || sampler > 16)
    throw FormatException(
      '${visual.id}: material excede presupuesto de parámetros.',
    );
  final bytes = File(binary).readAsBytesSync();
  final result = <String, Object>{
    'compilerHash': digest,
    'asset': 'packages/visual_catalog/$asset',
    'assetHash': _hash(bytes),
    'metalSource': File(metal).readAsStringSync(),
    'entryPoint': reflected['entrypoint'],
    'floatCount': offset,
    'samplerCount': sampler,
    'uniforms': fields,
  };
  writeCreatorFile(File('${catalog.path}/$asset'), bytes);
  writeCreatorFile(cache, utf8.encode(jsonEncode(result)));
  return result;
}
