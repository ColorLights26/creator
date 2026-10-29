import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/studio/visual_collections.dart';
import '../lib/studio/visual_uploads.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the bundled October cleanup retains only the two completed groups',
    () async {
      final uploads = decodeStudioVisualUploads(
        File('assets/visual_uploads.json').readAsStringSync(),
      );
      final all = buildStudioVisualCollections(uploads);
      final curated = await loadStudioVisualCollections();
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
      expect(
        curated.where((group) => !inPeriod(group)).map((group) => group.id),
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
    ]) {
      expect(
        () => decodeHiddenStudioCollectionIds(source),
        throwsFormatException,
      );
    }
  });
}
