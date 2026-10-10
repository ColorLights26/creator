/// Build-time only. Never imported by the application runtime.
///
/// The build manifest is the complete identity of how a Creator catalog draws
/// and costs beyond the authored sources: the shared C++ SDK and its ABI, the
/// iOS runtime the Creator path compiles (`SceneCatalog*.swift`, the signal
/// frame and the production output allocator), the material compiler of the
/// Flutter SDK, the bundled images, the test tools, the surface profiles and
/// the energy contract copy. The normal hook (`studio/tool/compile_visuals.dart`
/// through `build_catalog_assets.dart`) writes it next to the catalog as
/// `assets/creator_build_manifest.json`; Studio, the readiness registry and the
/// app approval compare its `hash`. Only file contents are hashed, never paths
/// or times, so two machines with the same sources and SDK agree.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'native_compiler.dart';

const creatorBuildManifestSchemaVersion = 1;

/// File name of the manifest inside `packages/visual_catalog/assets`.
const creatorBuildManifestFileName = 'creator_build_manifest.json';

/// Surfaces the pass gate replays (`authored_probe.cpp` `surfaces[]`): output
/// pixels, logical height and the full-screen passes that fit in 128 MiB.
/// The probe's `static_assert` keeps these numbers and the template in step.
const creatorSurfaceProfiles = <String, Map<String, int>>{
  'iPhone': {
    'width': 664,
    'height': 1440,
    'logicalHeight': 852,
    'maxPasses': 35,
  },
  'iPad': {
    'width': 900,
    'height': 1296,
    'logicalHeight': 1180,
    'maxPasses': 28,
  },
};
const creatorRendererMaxPasses = 192;
const creatorRendererMaxRetainedBytes = 128 * 1024 * 1024;

String _sha256(List<int> bytes) => sha256.convert(bytes).toString();

String canonicalJson(Object? value) => jsonEncode(_sorted(value));
Object? _sorted(Object? value) => switch (value) {
  Map<Object?, Object?>() => {
    for (final key in value.keys.map((key) => '$key').toList()..sort())
      key: _sorted(value[key]),
  },
  List<Object?>() => [for (final item in value) _sorted(item)],
  _ => value,
};

/// Hash of a named set of files: name and content hash per file, in order.
Map<String, Object?> _fileSet(List<File> files, String what) {
  final entries = <String, String>{};
  for (final file in files) {
    if (!file.existsSync()) throw StateError('Falta $what: ${file.path}');
    entries[file.uri.pathSegments.last] = _sha256(file.readAsBytesSync());
  }
  return {
    'files': entries,
    'hash': _sha256(utf8.encode(canonicalJson(entries))),
  };
}

/// The complete production runtime, including cadence, allocation and output
/// size. Changes outside the isolated Metal harness invalidate device cards too.
final _allocatorPattern = RegExp(
  r'@available\(iOS 15\.0, \*\)\n(?:private )?final class SceneSurfaceNativeOutputAllocator \{.*?^\}',
  multiLine: true,
  dotAll: true,
);

Map<String, Object?> creatorRuntimeIdentity(Directory repo) {
  final runtime = Directory(
    '${repo.path}/packages/scene_compositor/ios/Classes/Runtime',
  );
  if (!runtime.existsSync()) {
    throw StateError('Falta el runtime iOS en ${runtime.path}');
  }
  final swift =
      runtime
          .listSync(followLinks: false)
          .whereType<File>()
          .where((f) => f.path.endsWith('.swift'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final set = _fileSet([
    ...swift,
    File('${runtime.path}/SceneRenderSignalFrameV2.swift'),
  ], 'runtime iOS');
  final surface = File('${runtime.path}/SceneRenderV2ImageSurface.swift');
  final allocator =
      surface.existsSync()
          ? _allocatorPattern.firstMatch(surface.readAsStringSync())?.group(0)
          : null;
  if (allocator == null) {
    throw StateError(
      'Falta SceneSurfaceNativeOutputAllocator en ${surface.path}',
    );
  }
  final files = Map<String, String>.from(set['files'] as Map);
  files['SceneRenderV2ImageSurface.swift#SceneSurfaceNativeOutputAllocator'] =
      _sha256(utf8.encode(allocator));
  return {'files': files, 'hash': _sha256(utf8.encode(canonicalJson(files)))};
}

/// Files the readiness checks run; a changed check changes what "passed" means.
Map<String, Object?> creatorChecksIdentity(Directory repo) {
  final compositor = Directory('${repo.path}/packages/scene_compositor');
  final native = Directory('${repo.path}/packages/scene_program_native');
  return _fileSet([
    File('${native.path}/test/authored_probe.cpp'),
    File('${native.path}/test/check_native.py'),
    File('${native.path}/test/runtime_test.cpp'),
    File('${compositor.path}/ios/Tests/creator_scene_tests.swift'),
    File('${compositor.path}/ios/Tests/check_creator_scenes.py'),
    File('${compositor.path}/ios/Tests/creator_catalog_tests.swift'),
    File('${compositor.path}/ios/Tests/check_creator_catalog.rb'),
  ], 'herramienta de prueba');
}

/// Build, surface and evidence code whose changes invalidate measurements.
const creatorBuildInputPaths = [
  'packages/scene_compositor/lib/native_compiler.dart',
  'packages/scene_compositor/lib/authoring.dart',
  'packages/scene_compositor/lib/scene_compositor.dart',
  'packages/scene_compositor/lib/shader_compiler.dart',
  'packages/scene_compositor/lib/src/creator_command_canvas.dart',
  'packages/scene_compositor/lib/src/creator_catalog_decoder.dart',
  'packages/scene_compositor/lib/src/creator_visual_definition.dart',
  'packages/scene_compositor/lib/src/creator_visual_metadata.dart',
  'packages/scene_compositor/lib/src/creator_source_admission.dart',
  'packages/scene_compositor/lib/src/creator_variation.dart',
  'packages/scene_compositor/lib/src/creator_shader_program.dart',
  'packages/scene_compositor/lib/src/creator_native_program.dart',
  'packages/scene_compositor/lib/src/creator_shader_frame.dart',
  'packages/scene_compositor/lib/src/scene_compositor_controller.dart',
  'packages/scene_compositor/ios/Classes/SceneCompositorPlugin.swift',
  'packages/scene_compositor/lib/creator_build_manifest.dart',
  'packages/scene_compositor/lib/creator_device_card_evidence.dart',
  'packages/scene_compositor/lib/creator_trace_samples.dart',
  'packages/scene_compositor_host/lib/scene_compositor_host.dart',
  'packages/scene_compositor_host/ios/Classes/SceneCompositorHostPlugin.swift',
  'packages/scene_compositor_host/ios/Classes/SceneCompositorHostQaChannel.swift',
  'packages/scene_compositor/ios/scene_compositor.podspec',
  'packages/scene_compositor_host/ios/scene_compositor_host.podspec',
  'studio/tool/compile_visuals.dart',
  'studio/tool/build_catalog_assets.dart',
  'studio/tool/readiness.dart',
  'studio/lib/probe/energy_probe_record.dart',
  'studio/lib/probe/energy_probe_screen.dart',
  'studio/lib/probe/energy_probe_identity.dart',
  'studio/lib/probe/energy_probe_loud_signal.dart',
  'studio/lib/probe/energy_probe_profile.dart',
  'studio/lib/probe/energy_probe_spec.dart',
];

Map<String, Object?> creatorBuildInputsIdentity(Directory repo) {
  final files = <String, String>{};
  for (final path in creatorBuildInputPaths) {
    final file = File('${repo.path}/$path');
    if (!file.existsSync()) throw StateError('Falta entrada del build: $path');
    files[path] = _sha256(file.readAsBytesSync());
  }
  return {'files': files, 'hash': _sha256(utf8.encode(canonicalJson(files)))};
}

/// Every bundled image a program may sample, by catalog-relative path.
Map<String, Object?> creatorResourcesIdentity(Directory catalog) {
  final images = Directory('${catalog.path}/assets/images');
  final files = <String, String>{};
  if (images.existsSync()) {
    final entries =
        images
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((f) => !f.uri.pathSegments.last.startsWith('.'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in entries) {
      files[file.path.substring(catalog.path.length + 1)] = _sha256(
        file.readAsBytesSync(),
      );
    }
  }
  return {'files': files, 'hash': _sha256(utf8.encode(canonicalJson(files)))};
}

/// The registered energy contract copy (`readiness/energy_contract.json`,
/// written by `readiness.dart contract import`): revision and semantic hash,
/// or null when Creator has no copy yet.
Map<String, Object?>? creatorEnergyContractStamp(Directory catalog) {
  final file = File('${catalog.path}/readiness/energy_contract.json');
  if (!file.existsSync()) return null;
  final Object? json;
  try {
    json = jsonDecode(file.readAsStringSync());
  } on FormatException {
    return null;
  }
  if (json is! Map<String, Object?>) return null;
  final revision = json['revision'], hash = json['semanticHash'];
  if (revision is! String || hash is! String) return null;
  // The DATA the thresholds consume is bound by content, never by the
  // declared hash alone: editing `values` under the same revision and
  // semanticHash is another contract and another build identity. The import
  // timestamp and source path are excluded so importing the same DATA on
  // another machine preserves its identity.
  final values = json['values'];
  final provenance = json['provenance'];
  return {
    'revision': revision,
    'semanticHash': hash,
    'valuesHash': _sha256(
      utf8.encode(canonicalJson(values is Map ? values : json)),
    ),
    if (provenance is Map) 'provenance': provenance,
  };
}

/// Fingerprint of the production output allocator class as linked in
/// [surface] (`SceneRenderV2ImageSurface.swift`), or null when the file does
/// not carry it. The app compares the allocator it links against the
/// manifest slice instead of skipping it.
String? creatorAllocatorFingerprint(File surface) {
  if (!surface.existsSync()) return null;
  final match = _allocatorPattern
      .firstMatch(surface.readAsStringSync())
      ?.group(0);
  return match == null ? null : _sha256(utf8.encode(match));
}

/// Builds the manifest for [repo] (the Creator checkout), using [host] (a
/// resolved package: `studio` or the app) for the SDK and the material
/// compiler and [catalog] (`packages/visual_catalog`) for the resources and
/// the contract copy. [catalogJson] is the generated `creator_catalog.json`
/// text when known, so the manifest also names the catalog it was built with.
Map<String, Object?> creatorBuildManifest({
  required Directory repo,
  required Directory host,
  required Directory catalog,
  String? catalogJson,
}) {
  final engine = <String, Object?>{
    'sdkHash': creatorNativeSdkHash(host),
    'abi': 1,
    'glideRuntime': creatorGlideRuntime,
    'runtime': creatorRuntimeIdentity(repo),
    'materialToolchainHash': creatorMaterialToolchainHash(host),
    'resources': creatorResourcesIdentity(catalog),
    'checks': creatorChecksIdentity(repo),
    'buildInputs': creatorBuildInputsIdentity(repo),
    'surfaces': creatorSurfaceProfiles,
    'rendererMaxPasses': creatorRendererMaxPasses,
    'rendererMaxRetainedBytes': creatorRendererMaxRetainedBytes,
    'energyContract': creatorEnergyContractStamp(catalog),
  };
  return {
    'schemaVersion': creatorBuildManifestSchemaVersion,
    'hash': _sha256(utf8.encode(canonicalJson(engine))),
    'engine': engine,
    if (catalogJson != null) 'catalogSha256': _sha256(utf8.encode(catalogJson)),
  };
}

/// The stamp consumers compare: the manifest hash plus the two SDK fields
/// the catalog's `nativeBuild` also carries.
Map<String, Object?> creatorBuildStamp(Map<String, Object?> manifest) {
  final engine = manifest['engine'] as Map<String, Object?>? ?? const {};
  return {
    'buildHash': manifest['hash'],
    'sdkHash': engine['sdkHash'],
    'abi': engine['abi'],
  };
}

/// Reads a manifest written by the hook; null when absent or unreadable
/// (consumers then show "unknown", never a guess).
Map<String, Object?>? readCreatorBuildManifest(Directory catalog) {
  final file = File('${catalog.path}/assets/$creatorBuildManifestFileName');
  if (!file.existsSync()) return null;
  try {
    final json = jsonDecode(file.readAsStringSync());
    if (json is Map<String, Object?> &&
        json['schemaVersion'] == creatorBuildManifestSchemaVersion &&
        json['hash'] is String &&
        json['engine'] is Map) {
      return json;
    }
  } on FormatException {
    return null;
  }
  return null;
}
