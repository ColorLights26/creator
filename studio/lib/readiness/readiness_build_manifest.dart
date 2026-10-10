import 'dart:convert';

import 'package:crypto/crypto.dart';

const measuredCreatorBuildManifestAsset =
    'assets/measured_creator_build_manifest.json';

/// UI counterpart of resolveCreatorEvidenceManifest in tool/readiness.dart.
/// Evidence consumers may change while the sealed measured engine stays valid.
/// Runtime, SDK, resources, checks, surfaces and every other input stay exact.
String? resolveCreatorReadinessBuildHash(Object? current, Object? measured) {
  if (current is! Map<String, Object?> || current['schemaVersion'] != 1) {
    return null;
  }
  final currentHash = current['hash'];
  if (currentHash is! String || currentHash.isEmpty) return null;
  if (measured is! Map<String, Object?> ||
      current['schemaVersion'] != measured['schemaVersion'] ||
      !_coherent(current) ||
      !_coherent(measured)) {
    return currentHash;
  }
  const verifierPaths = {
    'packages/scene_compositor/lib/creator_device_card_evidence.dart',
    'studio/tool/readiness.dart',
  };
  final live = Map<String, Object?>.from(current['engine']! as Map);
  final old = measured['engine']! as Map;
  final inputs = Map<String, Object?>.from(live['buildInputs']! as Map);
  final files = Map<String, Object?>.from(inputs['files']! as Map);
  final oldFiles = (old['buildInputs']! as Map)['files']! as Map;
  if (files.length != oldFiles.length ||
      !files.keys.every(oldFiles.containsKey)) {
    return currentHash;
  }
  final changed = files.keys.where((path) => files[path] != oldFiles[path]);
  if (changed.any((path) => !verifierPaths.contains(path))) return currentHash;
  for (final path in changed.toList()) {
    files[path] = oldFiles[path];
  }
  inputs['files'] = files;
  inputs['hash'] = _hash(files);
  live['buildInputs'] = inputs;
  if (_canonicalJson(live) != _canonicalJson(old)) return currentHash;
  return measured['hash']! as String;
}

bool _coherent(Map<String, Object?> manifest) {
  final engine = manifest['engine'];
  if (engine is! Map<String, Object?> || manifest['hash'] != _hash(engine)) {
    return false;
  }
  final inputs = engine['buildInputs'];
  return inputs is Map<String, Object?> &&
      inputs['files'] is Map<String, Object?> &&
      inputs['hash'] == _hash(inputs['files']);
}

String _hash(Object? value) =>
    sha256.convert(utf8.encode(_canonicalJson(value))).toString();

String _canonicalJson(Object? value) => jsonEncode(_sorted(value));

Object? _sorted(Object? value) => switch (value) {
  Map<Object?, Object?>() => {
    for (final key in value.keys.map((key) => '$key').toList()..sort())
      key: _sorted(value[key]),
  },
  List<Object?>() => [for (final item in value) _sorted(item)],
  _ => value,
};
