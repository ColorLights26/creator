import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_compositor/scene_compositor.dart';
import 'package:visual_catalog/visual_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeCreatorCatalog);

  testWidgets(
    'catalog thumbnails are frozen cached pixels with overlay alpha',
    (tester) async {
      final index = creatorVisuals.indexWhere(
        (v) => v.role == CreatorRole.overlay && !v.isNative,
      );
      expect(index, greaterThanOrEqualTo(0));
      final visual = creatorVisuals[index];
      Widget poster(Key key) => MaterialApp(
        home: SizedBox(
          width: 128,
          height: 128,
          child: CreatorThumbnail(
            key: key,
            visual: visual,
            visualIndex: index,
            assets: creatorCatalogAssets,
          ),
        ),
      );
      await tester.pumpWidget(poster(const ValueKey('first')));
      for (var i = 0; i < 100 && find.byType(Image).evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
      }
      expect(find.byType(Image), findsOneWidget);
      final first =
          tester.widget<Image>(find.byType(Image)).image as MemoryImage;
      await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(first.bytes);
        final frame = await codec.getNextFrame();
        try {
          expect(frame.image.width, 256);
          expect(frame.image.height, 256);
          final pixels =
              (await frame.image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
          var transparent = 0;
          var visible = 0;
          for (var i = 3; i < pixels.lengthInBytes; i += 4) {
            if (pixels.getUint8(i) == 0) transparent++;
            if (pixels.getUint8(i) > 0) visible++;
          }
          expect(transparent, greaterThan(0));
          expect(visible, greaterThan(0));
        } finally {
          frame.image.dispose();
          codec.dispose();
        }
      });
      await tester.pumpWidget(poster(const ValueKey('second')));
      await tester.pump();
      final second =
          tester.widget<Image>(find.byType(Image)).image as MemoryImage;
      expect(identical(first.bytes, second.bytes), isTrue);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
