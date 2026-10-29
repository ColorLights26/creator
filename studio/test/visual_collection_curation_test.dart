import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/studio/visual_collections.dart';
import '../lib/studio/visual_uploads.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'recovery restores every hidden visual without repeating completed groups',
    () async {
      final uploads = decodeStudioVisualUploads(
        File('assets/visual_uploads.json').readAsStringSync(),
      );
      final all = buildStudioVisualCollections(uploads);
      final curated = await loadStudioVisualCollections();
      final recovered = curated.first;
      expect(recovered.id, 'recovered_20261021_23');
      expect(recovered.label, 'Recuperadas · 21–23 oct');
      expect(recovered.visualIds, hasLength(101));
      bool inPeriod(StudioVisualCollection group) =>
          RegExp(r' · 2[123] oct 2026$').hasMatch(group.label);

      expect(curated.where(inPeriod).map((group) => group.label), [
        'Reactivas mejoradas · Franco david · 23 oct 2026',
        'Reactivas mejoradas · Franco david · 22 oct 2026',
      ]);
      expect(curated.where(inPeriod).map((group) => group.visualIds.length), [
        46,
        49,
      ]);
      final hidden = decodeHiddenStudioCollectionIds(
        File('assets/visual_collection_curation.json').readAsStringSync(),
      );
      final previouslyHidden = {
        for (final group in all.where((group) => hidden.contains(group.id)))
          ...group.visualIds,
      };
      final completed = {
        for (final group in curated.where(inPeriod)) ...group.visualIds,
      };
      expect(recovered.visualIds.intersection(completed), isEmpty);
      expect({...recovered.visualIds, ...completed}, previouslyHidden);
      expect(
        recovered.visualIds.every(
          (id) => uploads.any((upload) => upload.visualId == id),
        ),
        isTrue,
        reason: 'Recovery uses the original IDs that own the existing votes.',
      );
      expect(
        curated
            .where((group) => !inPeriod(group) && group != recovered)
            .map((group) => group.id),
        all.where((group) => !inPeriod(group)).map((group) => group.id),
      );
    },
  );

  test('curation leaves subsequent deliveries visible', () {
    final hidden = decodeHiddenStudioCollectionIds(
      File('assets/visual_collection_curation.json').readAsStringSync(),
    );
    final groups = buildStudioVisualCollections(const [
      StudioVisualUpload(
        visualId: 'reactiva_future',
        author: 'Franco david',
        date: '2026-10-24',
      ),
    ], hiddenCollectionIds: hidden);
    expect(groups.first.label, 'Nuevos de Franco david · 24 oct 2026');
    expect(groups.first.visualIds, {'reactiva_future'});
    expect(groups[1].label, 'Reactivas · Franco david · 24 oct 2026');
  });

  test('invalid curation fails explicitly', () {
    for (final source in [
      '{}',
      '{"schemaVersion":1,"hiddenCollectionIds":[""]}',
      '{"schemaVersion":1,"hiddenCollectionIds":[4]}',
      '{"schemaVersion":1,"hiddenCollectionIds":["a","a"]}',
      '{"schemaVersion":1,"hiddenCollectionIds":[],"mergedCollections":{}}',
      '{"schemaVersion":1,"hiddenCollectionIds":[],"mergedCollections":[{"id":"r","label":"Recuperadas","sourceCollectionIds":[]}]}',
      '{"schemaVersion":1,"hiddenCollectionIds":[],"mergedCollections":[{"id":"r","label":"","sourceCollectionIds":["a"]}]}',
      '{"schemaVersion":1,"hiddenCollectionIds":[],"mergedCollections":[{"id":"r","label":"Recuperadas","sourceCollectionIds":["a","a"]}]}',
    ]) {
      expect(
        () => decodeHiddenStudioCollectionIds(source),
        throwsFormatException,
      );
    }
  });

  test(
    'a missing recovery source fails rather than silently dropping visuals',
    () {
      expect(
        () => buildStudioVisualCollections(
          const [],
          mergedCollections: const [
            StudioVisualCollectionMerge(
              id: 'recovered',
              label: 'Recuperadas',
              sourceCollectionIds: {'missing_delivery'},
            ),
          ],
        ),
        throwsFormatException,
      );
    },
  );
}
