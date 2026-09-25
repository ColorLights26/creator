import 'dart:async';
import 'dart:ui' as ui;

import 'package:visual_catalog/visual_catalog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_compositor/scene_compositor.dart';

const _size = Size(96, 128);

/// Exercises the compiled asset and actual Flutter raster pipeline. Readback is
/// confined to this test; the production surface retains its image on the GPU.
Future<Uint8List> _renderPixels(
  AndroidCreatorSession session,
  double hostTime,
) async {
  final painted = Completer<void>();
  void onPaint() {
    if (!painted.isCompleted) painted.complete();
  }

  session.repaint.addListener(onPaint);
  try {
    session.render(hostTime, reducedMotion: false);
    await painted.future.timeout(const Duration(seconds: 5));
    final image = session.image;
    expect(image, isNotNull);
    final bytes = await image!
        .toByteData(format: ui.ImageByteFormat.rawRgba)
        .timeout(const Duration(seconds: 5));
    expect(bytes, isNotNull);
    // A repaint notification precedes the session's in-flight cleanup. Let that
    // completion finish before manually requesting the next offscreen image.
    await Future<void>.delayed(Duration.zero);
    return Uint8List.fromList(
      bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
  } finally {
    session.repaint.removeListener(onPaint);
  }
}

int _differentChannels(Uint8List first, Uint8List second) {
  expect(first.length, second.length);
  var count = 0;
  for (var i = 0; i < first.length; i++) {
    if (first[i] != second[i]) count++;
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeCreatorCatalog);
  testWidgets(
    'Android controller loads and paints the generated shader asset',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final controller = SceneCompositorController(
        assets: creatorCatalogAssets,
      );
      try {
        await tester.runAsync(() async {
          await controller.setPlaying(false);
          await controller.setVisual(
            creatorVisuals.first,
            size: _size,
            pixelRatio: 1,
          );
        });
        expect(controller.error, isNull);
        expect(controller.textureId, isNull);
        final preview = controller.preview! as AndroidCreatorPreview;
        final painted = Completer<void>();
        void onPaint() {
          if (!painted.isCompleted) painted.complete();
        }

        preview.session.repaint.addListener(onPaint);
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: Center(
                child: SizedBox(
                  width: _size.width,
                  height: _size.height,
                  child: preview,
                ),
              ),
            ),
          );
          await tester.runAsync(
            () => painted.future.timeout(const Duration(seconds: 5)),
          );
          expect(preview.session.image?.width, _size.width.toInt());
          expect(preview.session.image?.height, _size.height.toInt());
          expect(controller.error, isNull);
          expect(tester.takeException(), isNull);
        } finally {
          preview.session.repaint.removeListener(onPaint);
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(controller.close);
        controller.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'real shader pixels move, pause and respond to canonical signals',
    (tester) async {
      final errors = <Object>[];
      final session = await tester.runAsync(
        () => AndroidCreatorSession.create(
          visual: creatorVisuals.first,
          visualIndex: 0,
          shaderAsset: creatorCatalogAssets.shaderAsset,
          size: _size,
          pixelRatio: 1,
          reactive: true,
          playing: true,
          onError: (error, _) => errors.add(error),
        ),
      );
      expect(session, isNotNull);
      final renderer = session!;
      try {
        await tester.runAsync(() async {
          final initial = await _renderPixels(renderer, 0);
          expect(initial.length, 96 * 128 * 4);
          final colors = <int>{};
          for (var i = 0; i < initial.length; i += 4) {
            colors.add(initial[i] << 16 | initial[i + 1] << 8 | initial[i + 2]);
            expect(initial[i + 3], 255);
          }
          expect(colors.length, greaterThan(100));

          final moved = await _renderPixels(renderer, .25);
          expect(_differentChannels(initial, moved), greaterThan(100));
          renderer.setPlaying(false);
          final heldImage = renderer.image!;
          renderer.render(.5, reducedMotion: false);
          renderer.render(.75, reducedMotion: false);
          await Future<void>.delayed(Duration.zero);
          expect(identical(renderer.image, heldImage), isTrue);
          final paused = await heldImage.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          expect(_differentChannels(moved, paused!.buffer.asUint8List()), 0);

          final fixture = createSyntheticSceneSignalRecording();
          final activeSample = fixture.samples.firstWhere(
            (sample) => sample.frame.available && sample.frame.musicActive,
          );
          renderer.setPlaying(true);
          renderer.reset(reactive: true, seed: fixture.qaSessionSeed);
          renderer.consume(activeSample.frame);
          final reactive = await _renderPixels(renderer, .75);
          renderer.reset(reactive: false, seed: fixture.qaSessionSeed);
          renderer.consume(activeSample.frame);
          final independent = await _renderPixels(renderer, .75);
          expect(_differentChannels(reactive, independent), greaterThan(100));
          expect(errors, isEmpty);
        });
      } finally {
        await tester.runAsync(renderer.close);
      }
    },
  );
}
