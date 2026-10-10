import 'dart:convert';

import 'package:crypto/crypto.dart';
// Pure Dart (authoring.dart has no Flutter): the readiness tool shares it.
import 'package:scene_compositor/authoring.dart';

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
      // Only when declared, so visuals without modifiers keep their votes.
      // Names and option texts are cosmetic (a choice sends its index);
      // ranges and initial values change the look.
      if (visual.modifiers.isNotEmpty)
        'modifiers': [
          for (final modifier in visual.modifiers)
            {...modifier.toMap()}
              ..remove('label')
              ..remove('options'),
        ],
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
