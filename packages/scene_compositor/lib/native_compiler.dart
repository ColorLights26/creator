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
  final probeCases = <String>[];
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
          // The generated reader and transitions are compiled into the
          // program: only what changes the C++ counts, never the names.
          if (visual.modifiers.isNotEmpty) [
            creatorGlideRuntime,
            for (final modifier in visual.modifiers)
              {
                'id': modifier.id,
                'kind': modifier.kind.name,
                'min': modifier.lower,
                'max': modifier.upper,
                'value': modifier.value.toDouble(),
              },
          ],
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
    declarations.writeln(creatorModifierReader(visual));
    if (visual.modifiers.isNotEmpty) {
      declarations.writeln(creatorGlideReader(visual));
    }
    declarations.writeln(
      '#line ${visual.sourceLine} ${jsonEncode(visual.sourceFile)}',
    );
    declarations.writeln(visual.nativeSource);
    declarations.writeln('#line 1 "creator_programs.inc"');
    if (visual.modifiers.isEmpty) {
      declarations.writeln(
        'std::unique_ptr<creator::Scene> make() { return std::make_unique<Visual>(); }\n}',
      );
    } else {
      declarations.writeln(creatorGlideWrapper(visual));
      declarations.writeln(
        'std::unique_ptr<creator::Scene> make() { return std::make_unique<CreatorGlideScene_>(); }\n}',
      );
    }
    if (visual.modifiers.isNotEmpty) probeCases.add(_probeCase(visual));
    entries.add(
      '{${jsonEncode(visual.programId)}, ${jsonEncode(hash)}, &authored_${visual.id}::make, {${materials.map(jsonEncode).join(',')}}, {${images.map(jsonEncode).join(',')}}, {${visual.modifiers.map((m) => _floatLiteral(m.value.toDouble())).join(',')}}}',
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
  writeCreatorFile(
    File('${output.path}/creator_probe_cases.inc'),
    utf8.encode(
      '// Generated for the native checks only; never compiled into an app.\n'
      '#include <array>\n#include <vector>\n'
      'struct CreatorProbeModifier { const char* id; int kind; float lower, upper, value; };\n'
      'struct CreatorProbeVariation { const char* name; std::array<float, 4> controls; std::vector<float> modifiers; };\n'
      'struct CreatorProbeCase { const char* program; std::vector<CreatorProbeModifier> modifiers; std::vector<CreatorProbeVariation> variations; };\n'
      'inline const std::vector<CreatorProbeCase>& creatorProbeCases() {\n'
      '  static const std::vector<CreatorProbeCase> cases = {${probeCases.join(',\n')}};\n'
      '  return cases;\n}\n',
    ),
  );
  return {'schemaVersion': 1, 'visuals': manifests};
}

/// The typed `modifiers(f)` reader placed before the author's code: one field
/// per declared modifier, already clamped to its range. Visuals without
/// modifiers get an empty one, so a misspelled field is a compile error.
String creatorModifierReader(CreatorVisualDefinition visual) {
  final fields = StringBuffer();
  final values = <String>[];
  for (var i = 0; i < visual.modifiers.length; i++) {
    final modifier = visual.modifiers[i];
    final raw = 'f.modifiers[$i]';
    final range =
        '${_floatLiteral(modifier.lower)}, ${_floatLiteral(modifier.upper)}';
    switch (modifier.kind) {
      case CreatorModifierKind.slider:
        fields.write(' float ${modifier.id};');
        values.add('std::clamp($raw, $range)');
      case CreatorModifierKind.steps:
      case CreatorModifierKind.choice:
        fields.write(' int ${modifier.id};');
        values.add('int(std::lround(std::clamp($raw, $range)))');
      case CreatorModifierKind.toggle:
        fields.write(' bool ${modifier.id};');
        values.add('$raw > .5f');
    }
  }
  return '// Modificadores declarados en ${visual.sourceFile}: modifiers(f).<id>.\n'
      'struct Modifiers {$fields };\n'
      'inline Modifiers modifiers(const Frame& f) { (void)f; return {${values.join(', ')}}; }';
}

/// One program's modifiers (kind index as in [CreatorModifierKind]) and
/// resolved variations, for the native sweep in CI and the app approval.
String _probeCase(CreatorVisualDefinition visual) {
  final modifiers = [
    for (final modifier in visual.modifiers)
      '{${jsonEncode(modifier.id)}, ${modifier.kind.index}, '
          '${_floatLiteral(modifier.lower)}, ${_floatLiteral(modifier.upper)}, '
          '${_floatLiteral(modifier.value.toDouble())}}',
  ];
  final variations = [
    for (final variation in visual.variations)
      if (variation.resolve(visual) case final resolved)
        '{${jsonEncode(variation.name)}, '
            '{${resolved.controls.toMap().values.map(_floatLiteral).join(', ')}}, '
            '{${resolved.modifiers.values.map(_floatLiteral).join(', ')}}}',
  ];
  return '{${jsonEncode(visual.programId)}, {${modifiers.join(', ')}}, '
      '{${variations.join(', ')}}}';
}

/// Bump when the generated reader or transition code changes behavior, so a
/// program built with the old code never matches a newer catalog.
const creatorGlideRuntime = 1;

/// Seconds a slider, steps or toggle takes to cover ~63% of a change, and a
/// choice to finish its crossfade.
const _glideSeconds = '.25f', _choiceSeconds = '.45f';

/// `glide(f)`: the same modifiers as transitions. Sliders and steps glide as
/// decimals, a toggle fades 0..1 and a choice exposes crossfade weights.
/// Emitted only for visuals that declare modifiers.
String creatorGlideReader(CreatorVisualDefinition visual) {
  final fields = StringBuffer();
  final values = <String>[];
  for (var i = 0; i < visual.modifiers.length; i++) {
    final modifier = visual.modifiers[i];
    final clamped =
        'std::clamp(f.modifiers[$i], ${_floatLiteral(modifier.lower)}, ${_floatLiteral(modifier.upper)})';
    if (modifier.kind == CreatorModifierKind.choice) {
      fields.write(' CreatorChoiceGlide ${modifier.id};');
      values.add('choice($i, int(std::lround($clamped)))');
    } else {
      fields.write(' float ${modifier.id};');
      values.add(clamped);
    }
  }
  return '''// Transiciones: glide(f).<id> se desliza hacia el valor elegido.
struct CreatorChoiceGlide {
  int from = 0, to = 0; float t = 1;
  // Weight of an option during the crossfade; the weights add up to 1.
  float weight(int option) const {
    const float s = t * t * (3 - 2 * t);
    return (option == to ? s : 0.f) + (option == from ? 1 - s : 0.f);
  }
};
struct CreatorGlide {$fields };
struct CreatorGlideState_ { const Frame* frame = nullptr; std::array<CreatorChoiceGlide, 8> choice{}; };
thread_local CreatorGlideState_ creatorGlide_;
inline CreatorGlide glide(const Frame& f) {
  // Only the frame the engine passes carries transitions; a copy is steady.
  const bool live = creatorGlide_.frame == &f;
  auto choice = [&](int i, int target) {
    return live ? creatorGlide_.choice[i] : CreatorChoiceGlide{target, target, 1};
  };
  (void)choice;
  return {${values.join(', ')}};
}''';
}

/// The scene the registry creates for a visual with modifiers: it eases the
/// requested values and hands the author a frame that already carries them.
/// Instant after creation or reset, while paused and with reduced motion.
String creatorGlideWrapper(CreatorVisualDefinition visual) {
  final count = visual.modifiers.length;
  final kinds = [
    for (final modifier in visual.modifiers) modifier.kind.index,
  ];
  final lower = [
    for (final modifier in visual.modifiers) _floatLiteral(modifier.lower),
  ];
  final upper = [
    for (final modifier in visual.modifiers) _floatLiteral(modifier.upper),
  ];
  final choice = CreatorModifierKind.choice.index;
  return '''class CreatorGlideScene_ final : public Scene {
  static constexpr int count_ = $count;
  static constexpr int kinds_[count_] = {${kinds.join(', ')}};
  static constexpr float lower_[count_] = {${lower.join(', ')}};
  static constexpr float upper_[count_] = {${upper.join(', ')}};
  static constexpr float glideSeconds_ = $_glideSeconds, choiceSeconds_ = $_choiceSeconds;
  Visual inner_;
  mutable std::array<float, 8> eased_{};
  mutable std::array<CreatorChoiceGlide, 8> choice_{};
  mutable bool ready_ = false, updated_ = false;
  mutable Frame view_;
  static float target_(const Frame& f, int i) { return std::clamp(f.modifiers[i], lower_[i], upper_[i]); }
  void snap_(const Frame& f) const {
    for (int i = 0; i < count_; i++) {
      const float value = target_(f, i);
      if (kinds_[i] == $choice) { const int option = int(std::lround(value)); choice_[i] = {option, option, 1}; }
      else eased_[i] = value;
    }
    ready_ = true;
  }
  void step_(const Frame& f) {
    if (!ready_ || f.reducedMotion) { snap_(f); return; }
    const float delta = float(f.delta), follow = 1 - std::exp(-delta / glideSeconds_);
    for (int i = 0; i < count_; i++) {
      const float value = target_(f, i);
      if (kinds_[i] == $choice) {
        auto& c = choice_[i];
        const int option = int(std::lround(value));
        if (option != c.to) {
          if (option == c.from) { std::swap(c.from, c.to); c.t = 1 - c.t; }
          else { c.from = c.t >= .5f ? c.to : c.from; c.to = option; c.t = 0; }
        }
        c.t = std::min(1.f, c.t + delta / choiceSeconds_);
      } else {
        float& eased = eased_[i];
        eased += (value - eased) * follow;
        if (std::fabs(value - eased) <= 1e-4f * (upper_[i] - lower_[i])) eased = value;
      }
    }
  }
  const Frame& view_of_(const Frame& f) const {
    view_ = f;
    for (int i = 0; i < count_; i++) if (kinds_[i] != $choice) view_.modifiers[i] = eased_[i];
    creatorGlide_.frame = &view_;
    creatorGlide_.choice = choice_;
    return view_;
  }
  struct Scope_ { ~Scope_() { creatorGlide_.frame = nullptr; } };
 public:
  void reset(uint32_t seed) override { ready_ = false; static_cast<Scene&>(inner_).reset(seed); }
  void update(const Frame& f) override {
    step_(f); updated_ = true;
    Scope_ scope; static_cast<Scene&>(inner_).update(view_of_(f));
  }
  void render(const Frame& f, Canvas& canvas) const override {
    // Without an update since the last render the engine is paused: show the
    // requested values at once.
    if (!updated_ || !ready_) snap_(f);
    updated_ = false;
    Scope_ scope; static_cast<const Scene&>(inner_).render(view_of_(f), canvas);
  }
};''';
}

String _floatLiteral(double value) {
  final text = value.toString();
  return '${text.contains('.') || text.contains('e') ? text : '$text.0'}f';
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
