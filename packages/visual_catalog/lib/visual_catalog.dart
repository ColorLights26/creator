/// Bundled catalog shared by the studio and its production consumer.
library;

import 'package:flutter/services.dart';
import 'package:scene_compositor/authoring.dart';

export 'package:scene_compositor/authoring.dart';

const creatorCatalogAssets = CreatorCatalogAssets(
  assetPackage: 'visual_catalog',
  catalogAsset: 'packages/visual_catalog/assets/creator_catalog.json',
  shaderAsset: 'packages/visual_catalog/shaders/creator_programs.frag',
  metadataAsset: 'packages/visual_catalog/assets/catalog_metadata.json',
);

List<CreatorVisualDefinition>? _visuals;
Future<void>? _initializing;

bool get creatorCatalogInitialized => _visuals != null;

/// Initialize before app services/catalog construction. The native build hook
/// generates JSON assets; a new source never needs a second run to refresh a
/// previously compiled import registry.
List<CreatorVisualDefinition> get creatorVisuals =>
    _visuals ??
    (throw StateError(
      'Call initializeCreatorCatalog before using the catalog.',
    ));

Future<void> initializeCreatorCatalog({AssetBundle? bundle}) {
  return _initializing ??= _load(bundle ?? rootBundle);
}

Future<void> _load(AssetBundle bundle) async {
  try {
    final contents = await Future.wait([
      bundle.loadString(creatorCatalogAssets.catalogAsset),
      bundle.loadString(creatorCatalogAssets.metadataAsset),
    ]);
    _visuals = decodeCreatorCatalog(
      runtimeJson: contents[0],
      metadataJson: contents[1],
    );
  } on Object {
    _initializing = null;
    rethrow;
  }
}
