import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:scene_compositor/scene_compositor.dart';

/// Fingerprint of what a reviewer actually sees and hears react.
///
/// Name, description and other catalog metadata can change without resetting
/// the team's votes; drawing code, materials, images and render parameters
/// cannot. Only author inputs count: compiler output in `nativeBuild`
/// (Metal source, toolchain and SDK hashes) differs between machines and
/// Flutter versions, so the same files would otherwise get different
/// revisions on each reviewer's computer.
String visualRevision(CreatorVisualDefinition visual) {
  final canonical = jsonEncode(
    _canonical({
      'shaderSource': visual.shaderSource,
      'nativeSource': visual.nativeSource,
      'shaderSources': visual.shaderSources,
      'images': visual.images,
      'imageHashes': visual.nativeBuild['imageHashes'],
      'role': visual.role.name,
      'reactivity': visual.reactivity.name,
      'framesPerSecond': visual.framesPerSecond,
      'seed': visual.seed,
      'colors': visual.colors,
      'controls': visual.controls.toMap(),
    }),
  );
  return sha256.convert(utf8.encode(canonical)).toString().substring(0, 16);
}

Object? _canonical(Object? value) => switch (value) {
  Map<Object?, Object?>() => {
    for (final key in value.keys.map((key) => '$key').toList()..sort())
      key: _canonical(value[key]),
  },
  List<Object?>() => [for (final item in value) _canonical(item)],
  _ => value,
};
