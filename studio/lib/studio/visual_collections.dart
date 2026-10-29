import 'dart:convert';

import 'package:flutter/services.dart';

import 'visual_uploads.dart';

/// Editorial groups for reviewing an upload without changing visual revisions.
class StudioVisualCollection {
  const StudioVisualCollection({
    required this.id,
    required this.label,
    required this.visualIds,
  });

  final String id;
  final String label;
  final Set<String> visualIds;
}

Future<List<StudioVisualCollection>> loadStudioVisualCollections({
  AssetBundle? bundle,
}) async {
  final assets = bundle ?? rootBundle;
  return buildStudioVisualCollections(
    decodeStudioVisualUploads(
      await assets.loadString('assets/visual_uploads.json'),
    ),
    hiddenCollectionIds: decodeHiddenStudioCollectionIds(
      await assets.loadString('assets/visual_collection_curation.json'),
    ),
  );
}

Set<String> decodeHiddenStudioCollectionIds(String source) {
  final data = jsonDecode(source);
  if (data is! Map ||
      data['schemaVersion'] != 1 ||
      data['hiddenCollectionIds'] is! List) {
    throw const FormatException('La selección de colecciones no es válida.');
  }
  final ids = <String>{};
  for (final id in data['hiddenCollectionIds'] as List) {
    if (id is! String || id.trim().isEmpty || !ids.add(id)) {
      throw const FormatException('ID de colección inválido o repetido.');
    }
  }
  return Set.unmodifiable(ids);
}

List<StudioVisualCollection> buildStudioVisualCollections(
  Iterable<StudioVisualUpload> uploads, {
  Set<String> hiddenCollectionIds = const {},
}) {
  final groups = <String, List<StudioVisualUpload>>{};
  final pending = <String>{};
  for (final upload in uploads) {
    if (upload.date == null) {
      pending.add(upload.visualId);
      continue;
    }
    final author = base64Url
        .encode(utf8.encode(upload.author!.trim().toLowerCase()))
        .replaceAll('=', '');
    final id = 'upload_${author}_${upload.date!.replaceAll('-', '')}';
    (groups[id] ??= []).add(upload);
  }
  final ordered =
      groups.entries.toList()..sort((a, b) {
        final byDate = b.value.first.date!.compareTo(a.value.first.date!);
        return byDate != 0 ? byDate : a.key.compareTo(b.key);
      });
  const months = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];
  String deliveryLabel(StudioVisualUpload upload) =>
      '${upload.author} · '
      '${int.parse(upload.date!.substring(8))} '
      '${months[int.parse(upload.date!.substring(5, 7)) - 1]} '
      '${upload.date!.substring(0, 4)}';
  final collections = <StudioVisualCollection>[
    for (final group in ordered) ...[
      StudioVisualCollection(
        id: group.key,
        label: 'Nuevos de ${deliveryLabel(group.value.first)}',
        visualIds: Set.unmodifiable(group.value.map((item) => item.visualId)),
      ),
      for (final family in StudioReactiveFamily.values)
        if (group.value.any((item) => item.reactiveFamily == family))
          StudioVisualCollection(
            id: '${group.key}_${family.name}',
            label: '${family.label} · ${deliveryLabel(group.value.first)}',
            visualIds: Set.unmodifiable(
              group.value
                  .where((item) => item.reactiveFamily == family)
                  .map((item) => item.visualId),
            ),
          ),
    ],
    if (pending.isNotEmpty)
      StudioVisualCollection(
        id: 'uploads_in_preparation',
        label: 'En preparación',
        visualIds: Set.unmodifiable(pending),
      ),
    ..._legacyStudioVisualCollections,
  ];
  return List.unmodifiable(
    collections.where(
      (collection) => !hiddenCollectionIds.contains(collection.id),
    ),
  );
}

// Historical editorial subsets remain available alongside automatic deliveries.
const _legacyStudioVisualCollections = <StudioVisualCollection>[
  StudioVisualCollection(
    id: 'franco_20261018_premium',
    label: 'Premium de Franco · 18 oct',
    visualIds: {
      'brasas_azules_premium',
      'brasas_cinematicas',
      'brasas_premium',
      'brasas_remolino_premium',
      'ceniza_premium',
      'chispas_premium',
      'chispas_bordes_premium',
      'destellos_dorados_premium',
      'estrellas_fugaces_premium',
      'fuego_azul',
      'hiperespacio_premium',
      'lluvia_dorada_premium',
      'lluvia_colores_premium',
      'lluvia_particulas_premium',
      'luces_flotantes_premium',
      'luciernagas_simples_premium',
      'nieve_premium',
      'nubes_azules',
      'particulas_viento_premium',
      'particulas_fuego',
      'polvo_flotante_premium',
      'pixeles_premium',
    },
  ),
  StudioVisualCollection(
    id: 'franco_20261018_simple',
    label: 'Simples de Franco · 18 oct',
    visualIds: {
      'brasas',
      'brasas_azules',
      'brasas_remolino',
      'ceniza',
      'chispas',
      'chispas_bordes',
      'destellos_dorados',
      'estrellas_fugaces',
      'hiperespacio',
      'lluvia_dorada',
      'lluvia_colores',
      'lluvia_particulas',
      'luces_flotantes',
      'luciernagas_simples',
      'nieve',
      'particulas_viento',
      'polvo_flotante',
      'pixeles',
    },
  ),
];
