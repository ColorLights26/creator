import 'dart:async';

import 'package:audiovisual_creator/studio/creator_studio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_compositor/scene_compositor.dart';

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

class _Controller extends SceneCompositorController {
  final visuals = <String>[];
  final viewports = <Size>[];
  final playing = <bool>[];
  final signals = <SceneRenderSignalFrameV2>[];
  final resets = <int?>[];
  final cleanup = <String>[];
  final actions = <String>[];
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
    expect(find.text('Demo sintética'), findsOneWidget);
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
      await tester.pump(const Duration(seconds: 9));
      await tester.pump(const Duration(seconds: 9));
      await _flush(tester);
      expect(controller.resets, hasLength(1));
      expect(controller.signals, isEmpty);
      expect(controller.playing.last, isTrue);
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
    },
  );

  testWidgets('disabling optional reaction stops unused source resets', (
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
    await tester.pump(const Duration(seconds: 9));
    await _flush(tester);
    expect(controller.resets, hasLength(2));
    await tester.ensureVisible(find.byKey(const ValueKey('reaction-switch')));
    await tester.tap(find.byKey(const ValueKey('reaction-switch')));
    await _flush(tester);
    final signalCount = controller.signals.length;
    await tester.pump(const Duration(seconds: 18));
    await _flush(tester);
    expect(controller.resets, hasLength(2));
    expect(controller.signals.length, signalCount);
    expect(controller.playing.last, isTrue);
    await tester.pumpWidget(const SizedBox());
    await _flush(tester);
  });

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
}
