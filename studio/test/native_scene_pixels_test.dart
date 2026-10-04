import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_compositor/src/creator_native_program.dart';
import 'package:scene_compositor/src/creator_command_canvas.dart';
import 'package:visual_catalog/visual_catalog.dart';
import 'package:visual_contract/visual_contract.dart';

SceneRenderSignalFrameV2 signal(int sequence, bool music) {
  final zero = SceneRenderSignalEventV2(
    serial: 0,
    active: false,
    timestampMicros: 0,
    strength: 0,
    band: SceneRenderSignalEventBandV2.none,
  );
  final hit = SceneRenderSignalEventV2(
    serial: sequence ~/ 12 + 1,
    active: music && sequence % 12 == 0,
    timestampMicros: sequence * 33333,
    strength: music ? .8 : 0,
    band: SceneRenderSignalEventBandV2.low,
  );
  return SceneRenderSignalFrameV2(
    sessionId: 2,
    sequence: sequence,
    audioTimestampMicros: sequence * 33333,
    available: music,
    fresh: true,
    musicActive: music,
    dynamics: List.filled(6, music ? .8 : 0),
    channels: List.filled(4, music ? .8 : 0),
    spectrumSummary: List.filled(7, 0),
    instantSpectrum: List.filled(31, 0),
    smoothedSpectrum: List.filled(31, 0),
    semantics: List.filled(6, 0),
    rhythm: [music ? 120 : 0, .5, 0, 0],
    onsets: List.filled(4, 0),
    tonalAvailable: false,
    tonal: List.filled(3, 0),
    impact: hit,
    accent: zero,
    beat: hit,
    flash: zero,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeCreatorCatalog);
  const library = String.fromEnvironment('CREATOR_TEST_LIBRARY');
  const output = String.fromEnvironment('CREATOR_PIXEL_OUTPUT');
  testWidgets(
    'native scenes draw through Flutter with identical canonical inputs',
    (tester) async {
      expect(
        library,
        isNotEmpty,
        reason: 'Build the native test library and pass CREATOR_TEST_LIBRARY.',
      );
      await tester.runAsync(() async {
        Directory(output).createSync(recursive: true);
        for (final visual in creatorVisuals.where((v) => v.isNative)) {
          final scene = CreatorNativeProgram(visual, libraryPath: library);
          final renderer = await CreatorCommandCanvas.prepare(visual);
          final shaders = <ui.Shader>[];
          ui.Picture? picture;
          ui.Image? image;
          try {
            scene.configure(
              reactive: visual.reactivity != CreatorReactivity.none,
              playing: true,
              hostTime: 0,
            );
            for (var i = 0; i <= 60; i++) {
              scene.consume(signal(i, true));
              scene.update(
                width: 320,
                height: 568,
                hostTime: i / 30,
                reducedMotion: false,
              );
            }
            final recorder = ui.PictureRecorder(), canvas = ui.Canvas(recorder);
            if (visual.role == CreatorRole.background)
              canvas.drawColor(ui.Color(visual.colors.first), ui.BlendMode.src);
            shaders.addAll(renderer.paint(canvas, scene.draw()));
            picture = recorder.endRecording();
            image = await picture.toImage(320, 568);
            final png =
                (await image.toByteData(format: ui.ImageByteFormat.png))!;
            File(
              '$output/${visual.programId}.png',
            ).writeAsBytesSync(png.buffer.asUint8List());
            final pixels =
                (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
            if (visual.id == 'composition_probe') {
              final samples =
                  jsonDecode(
                        File(
                          'test/fixtures/native_composition/pixels.json',
                        ).readAsStringSync(),
                      )
                      as List;
              for (final sample in samples) {
                final offset =
                    ((sample[1] as int) * 320 + (sample[0] as int)) * 4;
                for (var channel = 0; channel < 4; channel++) {
                  expect(
                    pixels.getUint8(offset + channel),
                    closeTo(sample[2][channel] as num, 2),
                    reason: 'composition $sample channel $channel',
                  );
                }
              }
            }
            final alpha = [
              for (var i = 3; i < pixels.lengthInBytes; i += 4)
                pixels.getUint8(i),
            ];
            expect(
              alpha.any((a) => a > 16),
              isTrue,
              reason: '${visual.id} must draw visible pixels (alpha > 16)',
            );
            if (visual.role == CreatorRole.background) {
              expect(
                alpha.every((a) => a == 255),
                isTrue,
                reason: '${visual.id} background must be fully opaque',
              );
            } else {
              expect(
                alpha.any((a) => a < 16),
                isTrue,
                reason:
                    '${visual.id} overlay must leave transparent areas (alpha < 16)',
              );
            }
            stdout.writeln('PASS pixel: ${visual.id}');
          } finally {
            image?.dispose();
            picture?.dispose();
            for (final shader in shaders) shader.dispose();
            renderer.dispose();
            scene.dispose();
          }
        }
      });
    },
    // CI supplies the compiled library and runs this explicitly.
    skip: library.isEmpty,
  );

  testWidgets(
    'declared modifiers reach the authored C++ and change its pixels',
    (tester) async {
      await tester.runAsync(() async {
        final visual = creatorVisuals.singleWhere(
          (v) => v.id == 'modifier_probe',
        );
        Future<List<int>> render(
          Map<String, double>? modifiers, {
          List<int>? palette,
        }) async {
          final scene = CreatorNativeProgram(visual, libraryPath: library);
          final renderer = await CreatorCommandCanvas.prepare(visual);
          final shaders = <ui.Shader>[];
          ui.Picture? picture;
          ui.Image? image;
          try {
            if (modifiers != null) scene.setModifiers(modifiers);
            if (palette != null) scene.setColors(palette);
            scene.configure(reactive: false, playing: true, hostTime: 0);
            scene.update(
              width: 320,
              height: 568,
              hostTime: 0,
              reducedMotion: false,
            );
            final recorder = ui.PictureRecorder(), canvas = ui.Canvas(recorder);
            shaders.addAll(renderer.paint(canvas, scene.draw()));
            picture = recorder.endRecording();
            image = await picture.toImage(320, 568);
            final data =
                (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
            return data.buffer.asUint8List();
          } finally {
            image?.dispose();
            picture?.dispose();
            for (final shader in shaders) shader.dispose();
            renderer.dispose();
            scene.dispose();
          }
        }

        void expectColor(List<int> pixels, int x, int y, List<int> rgba) {
          final offset = (y * 320 + x) * 4;
          expect(pixels.sublist(offset, offset + 4), [
            for (final c in rgba) closeTo(c, 2),
          ], reason: 'pixel ($x, $y)');
        }

        const black = [0, 0, 0, 255], white = [255, 255, 255, 255];
        const red = [255, 0, 0, 255];
        final initial = await render(null);
        expectColor(initial, 133, 115, white); // 4th square of 4
        expectColor(initial, 169, 115, black); // no 5th square
        expectColor(initial, 150, 220, red); // half width
        expectColor(initial, 200, 220, black);
        expectColor(initial, 160, 320, black); // frame off
        expectColor(initial, 160, 420, [0, 0, 255, 255]); // first option

        final changed = await render({
          'lados': 6,
          'ancho': 1,
          'marco': 1,
          'tono': 1,
        });
        expectColor(changed, 169, 115, white);
        expectColor(changed, 300, 220, red);
        expectColor(changed, 160, 320, [0, 255, 0, 255]);
        expectColor(changed, 160, 420, [255, 255, 0, 255]);
        // A live palette reaches the program without editing the visual.
        final recolored = await render(
          null,
          palette: const [0xff102030, 0xff00ffff, 0xffff0000, 0xff00ff00],
        );
        expectColor(recolored, 5, 5, [16, 32, 48, 255]);
        expectColor(recolored, 133, 115, [0, 255, 255, 255]);
        stdout.writeln('PASS modifiers: steps, slider, toggle and choice');
      });
    },
    skip: library.isEmpty,
  );
}
