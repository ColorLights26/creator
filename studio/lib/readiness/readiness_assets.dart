import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:visual_catalog/visual_catalog.dart';

import '../team_review/revision_links.dart';
import 'creator_readiness.dart';
import 'readiness_build_manifest.dart';

/// The studio export of the technical registry. A missing or malformed
/// asset means "unknown" for every visual: the studio keeps working and
/// says so, it never guesses a state.
Future<CreatorReadiness> loadCreatorReadiness({AssetBundle? bundle}) async {
  try {
    final json = await (bundle ?? rootBundle).loadString(creatorReadinessAsset);
    return CreatorReadiness.parse(json);
  } on Object {
    return const CreatorReadiness.none();
  }
}

/// The build manifest the generation hook bundled next to the catalog
/// (`creator_build_manifest.dart`), compared with the readiness engine stamp.
/// A sealed measured manifest may retain its stamp only after rederiving the
/// same strict evidence-consumer compatibility as the readiness tool.
Future<String?> loadCreatorBuildHash({AssetBundle? bundle}) async {
  final assets = bundle ?? rootBundle;
  Object? current;
  try {
    current = jsonDecode(await assets.loadString(creatorBuildManifestAsset));
  } on FormatException catch (error, stack) {
    _logBuildManifestFailure(creatorBuildManifestAsset, error, stack);
    return null;
  } on FlutterError catch (error, stack) {
    _logBuildManifestFailure(creatorBuildManifestAsset, error, stack);
    return null;
  }
  final currentHash = resolveCreatorReadinessBuildHash(current, null);
  if (currentHash == null) return null;
  try {
    final measured = jsonDecode(
      await assets.loadString(measuredCreatorBuildManifestAsset),
    );
    return resolveCreatorReadinessBuildHash(current, measured);
  } on FormatException catch (error, stack) {
    _logBuildManifestFailure(measuredCreatorBuildManifestAsset, error, stack);
    return currentHash;
  } on FlutterError catch (error, stack) {
    _logBuildManifestFailure(measuredCreatorBuildManifestAsset, error, stack);
    return currentHash;
  }
}

void _logBuildManifestFailure(String asset, Object error, StackTrace stack) {
  developer.log(
    'No se pudo cargar $asset: $error',
    name: 'audiovisual_creator',
    error: error,
    stackTrace: stack,
  );
}

/// Reviewed revision links. Missing or malformed: votes stay per revision.
Future<RevisionLinks> loadRevisionLinks({AssetBundle? bundle}) async {
  try {
    final json = await (bundle ?? rootBundle).loadString(
      creatorRevisionLinksAsset,
    );
    return RevisionLinks.parse(json);
  } on Object {
    return const RevisionLinks.none();
  }
}
