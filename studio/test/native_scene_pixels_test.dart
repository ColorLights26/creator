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
            expect(alpha.any((a) => a > 16), isTrue, reason: visual.id);
            if (visual.role == CreatorRole.background)
              expect(alpha.every((a) => a == 255), isTrue, reason: visual.id);
            else
              expect(alpha.any((a) => a < 16), isTrue, reason: visual.id);
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
}
