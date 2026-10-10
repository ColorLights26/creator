/// Who is being measured: the `creator` object of every record. Pure Dart.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:scene_compositor/authoring.dart';

import '../team_review/visual_revision.dart';
import 'energy_probe_profile.dart';

/// Bundled asset the catalog build may write; its `hash` is the build hash.
/// Optional: a studio without it reports null.
const energyProbeBuildManifestAsset =
    'packages/visual_catalog/assets/creator_build_manifest.json';

/// `nativeBuild.hash` of a native visual, or the SHA-256 of a shader
/// visual's source. Null for a native visual whose build carries no hash.
String? energyProbeProgramHash(CreatorVisualDefinition visual) {
  if (visual.isNative) {
    final hash = visual.nativeBuild['hash'];
    return hash is String && hash.isNotEmpty ? hash : null;
  }
  return sha256.convert(utf8.encode(visual.shaderSource)).toString();
}

/// The `hash` of a decoded build manifest, or null when absent or malformed.
String? energyProbeBuildHash(String? manifestJson) {
  if (manifestJson == null) return null;
  try {
    final decoded = jsonDecode(manifestJson);
    final hash = decoded is Map ? decoded['hash'] : null;
    return hash is String && hash.isNotEmpty ? hash : null;
  } on FormatException {
    return null;
  }
}

/// What feeds a reactive visual during the probe: the loud synthetic
/// recording, never a sensor. Named in every record (AGENTS.md: synthetic
/// fixtures are always identified).
const energyProbeSyntheticSignal = 'synthetic_loud';

/// The `creator` object: program identity, revision, profile, seed and the
/// signal source.
Map<String, Object?> energyProbeCreatorIdentity({
  required CreatorVisualDefinition visual,
  required EnergyProbeProfile profile,
  required bool reactive,
  required int seed,
  String? buildHash,
}) => {
  'visualId': visual.id,
  'programId': visual.programId,
  'kind': visual.isNative ? 'native' : 'shader',
  'programHash': energyProbeProgramHash(visual),
  'revision': visualRevision(visual),
  'buildHash': buildHash,
  'profile': profile.toMap(),
  'framesPerSecond': visual.framesPerSecond,
  'reactive': reactive,
  'signal': reactive ? energyProbeSyntheticSignal : null,
  'role': visual.role.name,
  'reactivity': visual.reactivity.name,
  'seed': seed,
};
