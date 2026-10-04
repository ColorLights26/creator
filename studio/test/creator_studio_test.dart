import 'dart:async';

import 'package:audiovisual_creator/studio/creator_studio.dart';
import 'package:audiovisual_creator/studio/studio_backdrop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_compositor/scene_compositor.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _aurora = CreatorVisualDefinition(
  id: 'aurora',
  name: 'Aurora',
  shaderSource: 'float4 paintVisual() { return float4(0); }',
);
const _plasma = CreatorVisualDefinition(
  id: 'plasma',
  name: 'Plasma',
  shaderSource: 'float4 paintVisual() { return float4(0); }',
);
const _quiet = CreatorVisualDefinition(
  id: 'quiet',
  name: 'Sin música',
  reactivity: CreatorReactivity.none,
  shaderSource: 'vec4 paintVisual() { return vec4(0); }',
);

const _galaxy = CreatorVisualDefinition(
  id: 'galaxia',
  name: 'Galaxia',
  nativeSource:
      'class Visual final : public Scene { float turn = f.delta * f.speed; };',
  modifiers: [
    CreatorModifier.steps('brazos', 'Brazos', min: 2, max: 6, value: 4),
    CreatorModifier.slider(
      'grosor',
      'Grosor',
      min: .004,
      max: .02,
      value: .004,
    ),
    CreatorModifier.toggle('nucleo', 'Núcleo', value: true),
    CreatorModifier.choice(
      'estilo',
      'Estilo',
      options: ['Auto', 'Nítido', 'Nebuloso'],
    ),
  ],
  variations: [
    CreatorVariation('Tormenta', {
      'brazos': 6,
      'estilo': 'Nebuloso',
      'speed': 1.4,
    }),
  ],
);

class _Controller extends SceneCompositorController {
  final visuals = <String>[];
  final viewports = <Size>[];
  final playing = <bool>[];
  final signals = <SceneRenderSignalFrameV2>[];
  final resets = <int?>[];
  final cleanup = <String>[];
  final actions = <String>[];
  final sentControls = <CreatorControls>[];
  final sentModifiers = <Map<String, double>>[];
  bool _closed = false;
  Completer<void>? attachGate;
  Object? attachError;
  Widget? surface;

  @override
  int? get textureId => visuals.isEmpty || surface != null ? null : 7;
  @override
  Widget? get preview => visuals.isEmpty ? null : surface;
  @override
  String? get error => null;

  @override
  Future<void> setVisual(
    CreatorVisualDefinition visual, {
    required Size size,
    required double pixelRatio,
  }) async {
    if (attachGate case final Completer<void> gate) await gate.future;
    if (attachError case final Object failure) throw failure;
    visuals.add(visual.id);
    viewports.add(size);
    notifyListeners();
  }

  @override
  Future<void> resize(Size size, double pixelRatio) async {}
  @override
  Future<void> setPlaying(bool value) async {
    playing.add(value);
    actions.add('playing:$value');
  }

  @override
  Future<void> setReactive(bool value) async {}
  @override
  Future<void> setControls(CreatorControls controls) async {
    sentControls.add(controls);
  }

  @override
  Future<void> setModifiers(Map<String, double> values) async {
    sentModifiers.add(values);
  }

  @override
  Future<void> sendSignal(SceneRenderSignalFrameV2 frame) async {
    signals.add(frame);
    actions.add('signal');
  }

  @override
  Future<void> reset({int? qaSessionSeed}) async {
    resets.add(qaSessionSeed);
    actions.add('reset');
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    cleanup.add('close');
  }

  @override
  void dispose() {
    cleanup.add('dispose');
    super.dispose();
  }
}

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('preview fills the display behind safe overlay controls', (
    tester,
  ) async {
    final controller = _Controller();
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);
    for (final size in [
      const Size(390, 844),
      const Size(844, 390),
      const Size(1024, 1366),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          home: CreatorStudio(
            catalogBuilder: () => [_aurora],
            controllerFactory: () => controller,
            recordingsLoader: () async => [],
            thumbnailBuilder: (_, _) => const SizedBox(),
          ),
        ),
      );
      await _flush(tester);
      final surface = tester.getRect(
        find.byKey(const ValueKey('visual-surface')),
      );
      expect(surface, Offset.zero & size);
      expect(tester.getRect(find.byType(Texture)), surface);
      final controls = tester.getRect(
        find.byKey(const ValueKey('studio-controls-overlay')),
      );
      expect(surface.contains(controls.topLeft), isTrue);
      expect(controls.bottom, lessThanOrEqualTo(size.height - 34));
      // The detailed signal (and its switch) opens from the strip; the view
      // keeps it open across the sizes of this loop.
      if (find.byKey(const ValueKey('reaction-switch')).evaluate().isEmpty) {
        await tester.ensureVisible(find.byKey(const ValueKey('audio-strip')));
        await tester.tap(find.byKey(const ValueKey('audio-strip')));
        await tester.pump();
      }
      await tester.ensureVisible(find.byKey(const ValueKey('reaction-switch')));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(controller.visuals, ['aurora']);
    }
    await tester.pumpWidget(const SizedBox());
    await _flush(tester);
  });

  testWidgets('selects every definition using one compositor', (tester) async {
    final controller = _Controller();
    var creations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CreatorStudio(
          catalogBuilder: () => [_aurora, _plasma],
          controllerFactory: () {
            creations++;
            return controller;
          },
          recordingsLoader: () async => [],
          thumbnailBuilder: (_, _) => const SizedBox(),
        ),
      ),
    );
    await _flush(tester);
    expect(controller.visuals.last, 'aurora');
    expect(find.byType(Texture), findsOneWidget);
    expect(controller.viewports.last, tester.getSize(find.byType(Texture)));
    expect(find.byKey(const ValueKey('audio-chip-0')), findsOneWidget);
    expect(find.text('Demo'), findsOneWidget);
    expect(
      controller.resets.single,
      createSyntheticSceneSignalRecording().qaSessionSeed,
    );

    await tester.tap(find.byKey(const ValueKey('visual-selector')));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Plasma').last);
    await _flush(tester);

    expect(controller.visuals.last, 'plasma');
    expect(creations, 1);
    await tester.pumpWidget(const SizedBox());
    await _flush(tester);
    expect(controller.cleanup, ['close', 'dispose']);
  });

  testWidgets('reassemble rereads the catalog and removes stale selection', (
    tester,
  ) async {
    final controller = _Controller();
    var definitions = <CreatorVisualDefinition>[_aurora];
    await tester.pumpWidget(
      MaterialApp(
        home: CreatorStudio(
          catalogBuilder: () => definitions,
          controllerFactory: () => controller,
          recordingsLoader: () async => [],
          thumbnailBuilder: (_, _) => const SizedBox(),
        ),
      ),
    );
    await _flush(tester);
    definitions = [_plasma];
    tester.binding.buildOwner!.reassemble(tester.binding.rootElement!);
    await _flush(tester);
    expect(find.text('Plasma'), findsOneWidget);
    expect(find.text('Aurora'), findsNothing);
    expect(controller.visuals.last, 'plasma');
    await tester.pumpWidget(const SizedBox());
    await _flush(tester);
  });

  testWidgets('hosts an Android shader surface without creating a texture', (
    tester,
  ) async {
    final controller =
        _Controller()
          ..surface = const ColoredBox(
            key: ValueKey('android-shader-surface'),
            color: Colors.black,
          );
    await tester.pumpWidget(
      MaterialApp(
        home: CreatorStudio(
          catalogBuilder: () => [_aurora, _plasma],
          controllerFactory: () => controller,
          recordingsLoader: () async => [],
          thumbnailBuilder: (_, _) => const SizedBox(),
        ),
      ),
    );
    await _flush(tester);
    expect(find.byType(Texture), findsNothing);
    expect(
      find.byKey(const ValueKey('android-shader-surface')),
      findsOneWidget,
    );
    expect(
      controller.viewports.last,
      tester.getSize(find.byKey(const ValueKey('visual-surface'))),
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('play-button')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const ValueKey('play-button')));
    await _flush(tester);
    expect(controller.playing.last, isFalse);
    await tester.pumpWidget(const SizedBox());
    await _flush(tester);
    expect(controller.cleanup, ['close', 'dispose']);
  });

  testWidgets('background pauses and preserves an explicit user pause', (
    tester,
  ) async {
    final controller = _Controller();
    await tester.pumpWidget(
      MaterialApp(
        home: CreatorStudio(
          catalogBuilder: () => [_aurora],
          controllerFactory: () => controller,
          recordingsLoader: () async => [],
          thumbnailBuilder: (_, _) => const SizedBox(),
        ),
      ),
    );
    await _flush(tester);
    expect(controller.playing.last, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _flush(tester);
    expect(controller.playing.last, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _flush(tester);
    expect(controller.playing.last, isTrue);

    await tester.tap(find.byKey(const ValueKey('play-button')));
    await _flush(tester);
    expect(controller.playing.last, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _flush(tester);
    expect(controller.playing.last, isFalse);
    await tester.pumpWidget(const SizedBox());
    await _flush(tester);
  });

  testWidgets('invalid catalog is visible and never starts the compositor', (
    tester,
  ) async {
    final controller = _Controller();
    await tester.pumpWidget(
      MaterialApp(
        home: CreatorStudio(
          catalogBuilder: () => [_aurora, _aurora],
          controllerFactory: () => controller,
          recordingsLoader: () async => [],
          thumbnailBuilder: (_, _) => const SizedBox(),
        ),
      ),
    );
    await _flush(tester);
    expect(find.textContaining('ID duplicado'), findsOneWidget);
    expect(controller.visuals, isEmpty);
    expect(controller.playing, isNot(contains(true)));
    await tester.pumpWidget(const SizedBox());
    await _flush(tester);
  });

  testWidgets('unsupported native rendering is a visible recoverable error', (
    tester,
  ) async {
    final controller =
        _Controller()
          ..attachError = UnsupportedError('Compositor no disponible');
    await tester.pumpWidget(
      MaterialApp(
        home: CreatorStudio(
          catalogBuilder: () => [_aurora],
          controllerFactory: () => controller,
          recordingsLoader: () async => [],
          thumbnailBuilder: (_, _) => const SizedBox(),
        ),
      ),
    );
    await _flush(tester);
    expect(find.textContaining('Compositor no disponible'), findsOneWidget);
    expect(controller.playing.last, isFalse);

    controller.attachError = null;
    await tester.tap(find.byTooltip('Recargar visuales'));
    await _flush(tester);
    expect(find.byType(Texture), findsOneWidget);
    expect(controller.playing.last, isTrue);
    await tester.pumpWidget(const SizedBox());
    await _flush(tester);
  });

  testWidgets(
    'leaving during an attach releases it without restarting playback',
    (tester) async {
      final gate = Completer<void>();
      final controller = _Controller()..attachGate = gate;
      await tester.pumpWidget(
        MaterialApp(
          home: CreatorStudio(
            catalogBuilder: () => [_aurora],
            controllerFactory: () => controller,
            recordingsLoader: () async => [],
            thumbnailBuilder: (_, _) => const SizedBox(),
          ),
        ),
      );
      await _flush(tester);
      await tester.pumpWidget(const SizedBox());
      gate.complete();
      await _flush(tester);
      expect(controller.playing, isNot(contains(true)));
      expect(controller.cleanup, ['close', 'dispose']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an independent visual does not restart at source loop boundaries',
    (tester) async {
      final controller = _Controller();
      await tester.pumpWidget(
        MaterialApp(
          home: CreatorStudio(
            catalogBuilder: () => [_quiet],
            controllerFactory: () => controller,
            recordingsLoader: () async => [],
            thumbnailBuilder: (_, _) => const SizedBox(),
          ),
        ),
      );
      await _flush(tester);
      expect(controller.resets, hasLength(1));
      expect(controller.signals, isEmpty);
      await tester.pump(
        createSyntheticSceneSignalRecording().duration +
            const Duration(seconds: 1),
      );
      await tester.pump(
        createSyntheticSceneSignalRecording().duration +
            const Duration(seconds: 1),
      );
      await _flush(tester);
      expect(controller.resets, hasLength(1));
      expect(controller.signals, isEmpty);
      expect(controller.playing.last, isTrue);
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
    },
  );

  testWidgets(
    'disabling optional reaction stops unused signals and preserves continuity across loop boundaries',
    (tester) async {
      final controller = _Controller();
      await tester.pumpWidget(
        MaterialApp(
          home: CreatorStudio(
            catalogBuilder: () => [_aurora],
            controllerFactory: () => controller,
            recordingsLoader: () async => [],
            thumbnailBuilder: (_, _) => const SizedBox(),
          ),
        ),
      );
      await _flush(tester);
      await tester.pump(
        createSyntheticSceneSignalRecording().duration +
            const Duration(seconds: 1),
      );
      await _flush(tester);
      expect(controller.resets, hasLength(1));
      expect(controller.signals.any((s) => s.sessionId > 1), isTrue);
      await tester.ensureVisible(find.byKey(const ValueKey('audio-strip')));
      await tester.tap(find.byKey(const ValueKey('audio-strip')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('reaction-switch')));
      await tester.tap(find.byKey(const ValueKey('reaction-switch')));
      await _flush(tester);
      final signalCount = controller.signals.length;
      await tester.pump(createSyntheticSceneSignalRecording().duration * 2);
      await _flush(tester);
      expect(controller.resets, hasLength(1));
      expect(controller.signals.length, signalCount);
      expect(controller.playing.last, isTrue);
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
    },
  );

  testWidgets(
    'a paused initial visual preserves its first signal until playing',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final controller = _Controller();
      await tester.pumpWidget(
        MaterialApp(
          home: CreatorStudio(
            catalogBuilder: () => [_aurora],
            controllerFactory: () => controller,
            recordingsLoader: () async => [],
            thumbnailBuilder: (_, _) => const SizedBox(),
          ),
        ),
      );
      await _flush(tester);
      expect(controller.resets, isEmpty);
      expect(controller.signals, isEmpty);
      expect(controller.playing, isNot(contains(true)));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _flush(tester);
      expect(controller.resets, hasLength(1));
      expect(controller.signals, isNotEmpty);
      expect(
        controller.actions.indexOf('playing:true'),
        lessThan(controller.actions.indexOf('reset')),
      );
      expect(
        controller.actions.indexOf('playing:true'),
        lessThan(controller.actions.indexOf('signal')),
      );
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
    },
  );

  testWidgets(
    'opens the first visual and no longer offers local approve or discard',
    (tester) async {
      final controller = _Controller();
      await tester.pumpWidget(
        MaterialApp(
          home: CreatorStudio(
            catalogBuilder: () => [_aurora, _plasma],
            controllerFactory: () => controller,
            recordingsLoader: () async => [],
            thumbnailBuilder: (_, _) => const SizedBox(),
          ),
        ),
      );
      await _flush(tester);
      expect(controller.visuals.last, 'aurora');
      // The team's vote decides now; the studio has no curation buttons.
      expect(find.text('Aprobar'), findsNothing);
      expect(find.text('Descartar'), findsNothing);
      expect(find.text('PENDIENTE DE REVISIÓN'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
    },
  );

  testWidgets('the list searches by name, ignoring accents and case', (
    tester,
  ) async {
    final controller = _Controller();
    await tester.pumpWidget(
      MaterialApp(
        home: CreatorStudio(
          catalogBuilder: () => [_aurora, _plasma, _quiet],
          controllerFactory: () => controller,
          recordingsLoader: () async => [],
          thumbnailBuilder: (_, _) => const SizedBox(),
        ),
      ),
    );
    await _flush(tester);
    expect(controller.visuals.last, 'aurora');

    await tester.tap(find.byKey(const ValueKey('visual-search-button')));
    await _flush(tester);
    final list = find.byType(ListView);
    Finder listed(String name) =>
        find.descendant(of: list, matching: find.text(name));
    expect(listed('Plasma'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('visual-search-field')),
      'MUSICA',
    );
    await tester.pump();
    expect(listed('Sin música'), findsOneWidget);
    expect(listed('Plasma'), findsNothing);
    expect(listed('Aurora'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('visual-search-field')),
      'zzz',
    );
    await tester.pump();
    expect(find.text('Ningún visual coincide con «zzz».'), findsOneWidget);

    // Enter opens the first match.
    await tester.enterText(
      find.byKey(const ValueKey('visual-search-field')),
      'plas',
    );
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _flush(tester);
    expect(controller.visuals.last, 'plasma');
    expect(find.byKey(const ValueKey('visual-search-field')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await _flush(tester);
  });

  testWidgets(
    'the alpha grid is the default backdrop; the picker offers many more',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = _Controller();
      await tester.pumpWidget(
        MaterialApp(
          home: CreatorStudio(
            catalogBuilder: () => [_aurora, _plasma],
            controllerFactory: () => controller,
            recordingsLoader: () async => [],
            thumbnailBuilder: (_, _) => const SizedBox(),
            backdropBuilder:
                (visual, _) =>
                    SizedBox.expand(key: ValueKey('still-${visual.id}')),
          ),
        ),
      );
      await _flush(tester);
      final checkerboard = find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.painter is CheckerboardPainter &&
            (w.painter! as CheckerboardPainter).squareSize == 20,
      );
      Color surfaceColor() =>
          tester
              .widget<ColoredBox>(find.byKey(const ValueKey('visual-surface')))
              .color;
      Future<void> pick(String id) async {
        final swatch = find.byKey(ValueKey('backdrop-$id'));
        await tester.ensureVisible(swatch);
        await tester.pump();
        await tester.tap(swatch);
        await tester.pump();
      }

      // Initially the alpha grid.
      expect(checkerboard, findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('toggle-background-mode-button')),
      );
      // Let the sheet finish sliding in before picking.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Fondo detrás del visual'), findsOneWidget);

      await pick('claro');
      expect(checkerboard, findsNothing);
      expect(surfaceColor(), const Color(0xFFF2F2F7));

      await pick('rojo');
      expect(
        find.descendant(
          of: find.byType(StudioBackdropFill),
          matching: find.byWidgetPredicate(
            (w) => w is ColoredBox && w.color == const Color(0xFFC62828),
          ),
        ),
        findsWidgets,
      );

      await pick('atardecer');
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              (w.decoration as BoxDecoration?)?.gradient is LinearGradient,
        ),
        findsWidgets,
      );

      // Catalog backgrounds appear frozen behind the overlay.
      await pick('visual:plasma');
      expect(find.byKey(const ValueKey('still-plasma')), findsOneWidget);

      await pick('alpha');
      expect(checkerboard, findsOneWidget);
      expect(find.byKey(const ValueKey('still-plasma')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
    },
  );

  Future<_Controller> pumpAdjustments(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final controller = _Controller();
    await tester.pumpWidget(
      MaterialApp(
        home: CreatorStudio(
          catalogBuilder: () => [_galaxy, _aurora],
          controllerFactory: () => controller,
          recordingsLoader: () async => [],
          thumbnailBuilder: (_, _) => const SizedBox(),
        ),
      ),
    );
    await _flush(tester);
    return controller;
  }

  Future<void> openAdjustments(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('visual-adjustments-button'));
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey(key));
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
    await _flush(tester);
  }

  Future<void> closeAdjustments(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets(
    'Ajustes changes modifiers live and keeps them across a track change',
    (tester) async {
      final controller = await pumpAdjustments(tester);
      expect(find.text('Ajustes · 4 modificadores'), findsOneWidget);
      expect(controller.sentModifiers, isEmpty);

      await openAdjustments(tester);
      expect(find.text('Ajustes · Galaxia'), findsOneWidget);
      expect(find.text('Brazos'), findsOneWidget);
      // Only the basics the code reads are shown (this one reads speed).
      expect(
        find.byKey(const ValueKey('adjustments-basic-speed')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('adjustments-basic-detail')),
        findsNothing,
      );

      await tapKey(tester, 'adjustments-modifier-estilo-2');
      expect(controller.sentModifiers.last, {
        'brazos': 4.0,
        'grosor': .004,
        'nucleo': 1.0,
        'estilo': 2.0,
      });
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('adjustments-modifier-nucleo')),
          matching: find.byType(Switch),
        ),
      );
      await _flush(tester);
      expect(controller.sentModifiers.last['nucleo'], 0);

      await closeAdjustments(tester);
      expect(
        find.text('Ajustes · 4 modificadores · cambiados'),
        findsOneWidget,
      );

      // Restarting the visual (new track, reload) brings back its initial
      // values; Ajustes sends the chosen ones again right after.
      final sent = controller.sentModifiers.length;
      await tester.tap(find.byTooltip('Recargar visuales'));
      await _flush(tester);
      expect(controller.visuals, ['galaxia', 'galaxia']);
      expect(controller.sentModifiers.length, sent + 1);
      expect(controller.sentModifiers.last, {
        'brazos': 4.0,
        'grosor': .004,
        'nucleo': 0.0,
        'estilo': 2.0,
      });

      await openAdjustments(tester);
      await tapKey(tester, 'adjustments-chip-original');
      expect(controller.sentModifiers.last, _galaxy.modifierDefaults);

      // Another visual starts from its own initial values and explains why
      // it has no modifiers of its own; coming back keeps the session.
      await closeAdjustments(tester);
      await tester.tap(find.byKey(const ValueKey('visual-selector')));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text('Aurora').last);
      await _flush(tester);
      expect(controller.visuals.last, 'aurora');
      expect(find.text('Ajustes'), findsOneWidget);
      await openAdjustments(tester);
      expect(
        find.byKey(const ValueKey('adjustments-no-modifiers')),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
    },
  );

  testWidgets(
    'looks: variations, dice, undo, hold to compare, another seed, saving',
    (tester) async {
      final controller = await pumpAdjustments(tester);
      await openAdjustments(tester);

      // An author variation: modifiers morph in the engine, basics in Dart.
      await tapKey(tester, 'adjustments-chip-Tormenta');
      await tester.pump(const Duration(milliseconds: 400));
      await _flush(tester);
      expect(controller.sentModifiers.last, {
        'brazos': 6.0,
        'grosor': .004,
        'nucleo': 1.0,
        'estilo': 2.0,
      });
      final speeds = [for (final c in controller.sentControls) c.speed];
      expect(speeds.last, 1.4);
      expect(speeds.where((v) => v > 1 && v < 1.4), isNotEmpty);

      // Variar changes something; Deshacer goes back to Tormenta.
      final before = controller.sentModifiers.last;
      await tapKey(tester, 'adjustments-vary');
      await tester.pump(const Duration(milliseconds: 400));
      await _flush(tester);
      final varied = {
        ...controller.sentModifiers.last,
        'speed': controller.sentControls.last.speed,
      };
      expect(varied, isNot({...before, 'speed': 1.4}));
      await tapKey(tester, 'adjustments-undo');
      await tester.pump(const Duration(milliseconds: 400));
      await _flush(tester);
      expect(controller.sentModifiers.last, before);
      expect(controller.sentControls.last.speed, 1.4);

      // Sorprender stays inside every declared range.
      await tapKey(tester, 'adjustments-surprise');
      await tester.pump(const Duration(milliseconds: 400));
      await _flush(tester);
      for (final modifier in _galaxy.modifiers) {
        expect(
          modifier.accepts(controller.sentModifiers.last[modifier.id]!),
          isTrue,
        );
      }

      // Guardar keeps the look as a chip.
      await tapKey(tester, 'adjustments-save');
      expect(
        find.byKey(const ValueKey('adjustments-mine-Mía 1')),
        findsOneWidget,
      );
      final saved = controller.sentModifiers.last;

      // Another seed restarts the same visual with another arrangement.
      final resets = controller.resets.length;
      await tester.tap(find.byKey(const ValueKey('adjustments-more')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Otra semilla'));
      await tester.pump(const Duration(milliseconds: 400));
      await _flush(tester);
      expect(controller.resets.length, resets + 1);
      expect(controller.resets.last, isNot(controller.resets.first));
      await closeAdjustments(tester);

      // Holding the visual shows the original; lifting brings the look back.
      final gesture = await tester.startGesture(const Offset(600, 300));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await _flush(tester);
      expect(find.byKey(const ValueKey('compare-label')), findsOneWidget);
      expect(controller.sentModifiers.last, _galaxy.modifierDefaults);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      await _flush(tester);
      expect(find.byKey(const ValueKey('compare-label')), findsNothing);
      expect(controller.sentModifiers.last, saved);

      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
    },
  );
}
