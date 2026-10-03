import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_compositor/scene_compositor.dart';
import 'package:visual_catalog/visual_catalog.dart';

// Its own file: thumbnails share one static render queue per isolate.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeCreatorCatalog);

  testWidgets('a backdrop still renders at the requested size', (tester) async {
    final index = creatorVisuals.indexWhere(
      (v) => v.role == CreatorRole.background && !v.isNative,
    );
    expect(index, greaterThanOrEqualTo(0));
    await tester.pumpWidget(
      MaterialApp(
        home: CreatorThumbnail(
          visual: creatorVisuals[index],
          visualIndex: index,
          assets: creatorCatalogAssets,
          size: 96,
        ),
      ),
    );
    for (var i = 0; i < 100 && find.byType(Image).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
    final still = tester.widget<Image>(find.byType(Image)).image as MemoryImage;
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(still.bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 96);
      expect(frame.image.height, 96);
      frame.image.dispose();
    });
  });
}
