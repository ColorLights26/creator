import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:visual_contract/visual_contract.dart';

import 'creator_visual_definition.dart';
import 'android_creator_surface.dart';

/// Owns one production SceneSurface session. No second renderer or audio engine.
class SceneCompositorController extends ChangeNotifier {
  SceneCompositorController({
    this.assets = const CreatorCatalogAssets(
      catalogAsset: 'assets/creator_catalog.json',
      shaderAsset: 'shaders/creator_programs.frag',
      metadataAsset: 'assets/creator_metadata.json',
    ),
  });

  final CreatorCatalogAssets assets;

  static const _channel = MethodChannel(
    'com.chic.colorlights/scene_surface_renderer',
  );
  static int _nextId = 0;
  Future<void> _pending = Future.value();
  CreatorVisualDefinition? _visual;
  CreatorControls? _controls;
  Size _size = Size.zero;
  double _pixelRatio = 1;
  static const _pipChannel = MethodChannel('com.chic.dev/picture_in_picture');
  static const _pipEvents = EventChannel(
    'com.chic.dev/picture_in_picture/events',
  );
  StreamSubscription<dynamic>? _pipSubscription;
  Map<Object?, Object?>? _pipIdentity;
  Completer<void>? _pipStopped;
  String? _documentGeneration;
  bool get pictureInPictureActive => _pipIdentity != null;
  String? _sessionId;
  int? _textureId;
  Widget? _preview;
  AndroidCreatorSession? _android;
  int _visualIndex = 0;
  int? _qaSeed;
  String? _error;
  bool _playing = true;
  bool _reactive = true;
  bool _disposed = false;
  bool _closed = false;

  int? get textureId => _textureId;
  Widget? get preview => _preview;
  String? get error => _error;

  Future<T?> _invoke<T>(String method, Map<String, Object> arguments) =>
      _channel
          .invokeMethod<T>(method, arguments)
          .timeout(const Duration(seconds: 8));

  Future<void> _queue(
    Future<void> Function() operation, {
    bool clearsError = true,
  }) {
    final next = _pending.then((_) async {
      if (_closed) throw StateError('The compositor has been closed.');
      final oldTexture = _textureId;
      final oldError = _error;
      final oldPreview = _preview;
      try {
        await operation();
        if (clearsError) _error = null;
      } on Object catch (error, stack) {
        _error = error.toString();
        developer.log(
          'Scene compositor operation failed',
          name: 'scene_compositor',
          error: error,
          stackTrace: stack,
        );
        rethrow;
      } finally {
        if (!_disposed &&
            (oldTexture != _textureId ||
                oldError != _error ||
                oldPreview != _preview)) {
          notifyListeners();
        }
      }
    });
    // Keep the ownership queue usable after errors, while returning the actual
    // failed Future to the UI. A failed detach retains its ID for a later retry.
    _pending = next.catchError((Object _) {});
    return next;
  }

  Future<void> setVisual(
    CreatorVisualDefinition visual, {
    required Size size,
    required double pixelRatio,
  }) => _queue(() async {
    validateCreatorCatalog([visual]);
    _validateViewport(size, pixelRatio);
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      throw UnsupportedError('El creador requiere iOS o Android.');
    }
    final catalog =
        jsonDecode(await rootBundle.loadString(assets.catalogAsset))
            as Map<String, dynamic>;
    final installedVisuals =
        (catalog['visuals'] as List).cast<Map<String, dynamic>>();
    final installed = installedVisuals.where(
      (entry) => entry['id'] == visual.id,
    );
    if (installed.length != 1 ||
        jsonEncode(installed.single) != jsonEncode(visual.toManifest())) {
      throw const FormatException(
        'La plantilla cambió. Detén la app y vuelve a ejecutarla para compilar los visuales.',
      );
    }
    await _detach();
    _visual = visual;
    _controls = visual.controls;
    _visualIndex = installedVisuals.indexWhere(
      (entry) => entry['id'] == visual.id,
    );
    _size = size;
    _pixelRatio = pixelRatio;
    _qaSeed = null;
    _reactive = visual.reactivity != CreatorReactivity.none;
    await _attach();
  });

  Future<void> resize(Size size, double pixelRatio) => _queue(() async {
    _validateViewport(size, pixelRatio);
    if (size == _size && pixelRatio == _pixelRatio) return;
    _size = size;
    _pixelRatio = pixelRatio;
    _android?.resize(size, pixelRatio);
    if (_sessionId != null) {
      await _invoke<Object>('updateViewport', _viewport());
    }
  }, clearsError: false);

  Future<void> setPlaying(bool playing) => _queue(() async {
    _playing = playing;
    _android?.setPlaying(playing);
    if (_sessionId != null) {
      await _invoke<Object>('setPlaying', {
        'sessionId': _sessionId!,
        'playing': playing,
      });
    }
  }, clearsError: false);

  Future<void> setReactive(bool reactive) => _queue(() async {
    final visual = _visual;
    if (visual == null || reactive == _reactive) return;
    if (visual.reactivity != CreatorReactivity.optional) {
      throw ArgumentError('This visual has fixed reactivity.');
    }
    if (_android != null) {
      _android!.setReactive(reactive);
      _reactive = reactive;
      return;
    }
    if (_sessionId != null) {
      await _invoke<Object>('updateDocument', {
        'sessionId': _sessionId!,
        'sceneDocument': visual.sceneDocument(
          width: _size.width,
          height: _size.height,
          reactive: reactive,
          qaSessionSeed: _qaSeed,
          liveControls: _controls,
        ),
      });
    }
    _reactive = reactive;
  });

  Future<void> setControls(CreatorControls controls) => _queue(() async {
    controls.validate();
    final visual = _visual;
    if (visual == null) throw StateError('No visual is installed.');
    if (_android != null) _android!.setControls(controls);
    if (_sessionId != null) {
      await _invoke<Object>('updateDocument', {
        'sessionId': _sessionId!,
        'sceneDocument': visual.sceneDocument(
          width: _size.width,
          height: _size.height,
          reactive: _reactive,
          qaSessionSeed: _qaSeed,
          liveControls: controls,
        ),
      });
    }
    _controls = controls;
  });

  Future<void> sendSignal(SceneRenderSignalFrameV2 frame) => _queue(() async {
    if (!_reactive) return;
    if (_android != null) {
      _android!.consume(frame);
      return;
    }
    if (_sessionId == null || !_reactive) return;
    await _invoke<Object>('updateSignalFrame', {
      'sessionId': _sessionId!,
      'frameBytes': frame.toBytes(),
    });
  }, clearsError: false);

  Future<void> reset({int? qaSessionSeed}) => _queue(() async {
    if (qaSessionSeed != null &&
        (qaSessionSeed < 0 || qaSessionSeed > 0xffffffff)) {
      throw const FormatException(
        'La semilla de la grabación no cabe en uint32. No se puede reproducir sin alterarla.',
      );
    }
    _qaSeed = qaSessionSeed;
    if (_android != null) {
      _android!.reset(reactive: _reactive, seed: qaSessionSeed);
      return;
    }
    await _detach();
    if (_visual != null) await _attach();
  });

  Map<String, Object> _viewport() => {
    'sessionId': _sessionId!,
    'width': _size.width,
    'height': _size.height,
    'devicePixelRatio': _pixelRatio,
  };

  Future<void> _attach() async {
    final visual = _visual!;
    if (defaultTargetPlatform == TargetPlatform.android) {
      final session = await AndroidCreatorSession.create(
        shaderAsset: assets.shaderAsset,
        visual: visual,
        visualIndex: _visualIndex,
        size: _size,
        pixelRatio: _pixelRatio,
        reactive: _reactive,
        playing: _playing,
        onError: (error, stack) {
          developer.log(
            'Android shader rendering failed',
            name: 'scene_compositor',
            error: error,
            stackTrace: stack,
          );
          if (_closed || _disposed) return;
          final message = error.toString();
          if (_error == message) return;
          _error = message;
          notifyListeners();
        },
      );
      if (_qaSeed != null) session.reset(reactive: _reactive, seed: _qaSeed);
      session.setControls(_controls ?? visual.controls);
      _android = session;
      _preview = AndroidCreatorPreview(
        key: ObjectKey(session),
        session: session,
      );
      return;
    }
    final supported = await _invoke<bool>('isSupported', const {});
    if (supported != true)
      throw UnsupportedError('El compositor nativo no está disponible.');
    _sessionId =
        'creator:${DateTime.now().microsecondsSinceEpoch}:${_nextId++}';
    try {
      final receipt = await _invoke<Map<Object?, Object?>>('attach', {
        ..._viewport(),
        'playing': _playing,
        'sceneDocument': visual.sceneDocument(
          width: _size.width,
          height: _size.height,
          reactive: _reactive,
          qaSessionSeed: _qaSeed,
          liveControls: _controls,
        ),
      });
      final texture = receipt?['textureId'];
      if (texture is! int || texture < 0)
        throw StateError('El compositor no devolvió una textura válida.');
      _textureId = texture;
      _documentGeneration = receipt?['documentGeneration'] as String?;
    } on PlatformException catch (error) {
      final diagnostics = await _invoke<Object>('creatorDiagnostics', const {});
      await _detach();
      throw PlatformException(
        code: error.code,
        message: '${error.message ?? error.code}\n${jsonEncode(diagnostics)}',
        details: error.details,
      );
    } on Object {
      await _detach();
      rethrow;
    }
  }

  Future<Map<Object?, Object?>?> startPerformanceProbe() =>
      _invoke<Map<Object?, Object?>>('startPerformanceProbe', {
        'sceneId': _visual!.programId,
      });

  Future<Map<Object?, Object?>?> stopPerformanceProbe(
    Map<Object?, Object?> identity,
  ) => _invoke<Map<Object?, Object?>>(
    'stopPerformanceProbe',
    identity.cast<String, Object>(),
  );

  Future<void> startPictureInPicture() => _queue(() async {
    if (_sessionId == null ||
        _documentGeneration == null ||
        _pipIdentity != null) {
      throw StateError('PiP necesita una escena nativa preparada.');
    }
    if (await _pipChannel.invokeMethod<bool>('isSupported') != true) {
      throw UnsupportedError('PiP no está disponible en este dispositivo.');
    }
    _pipSubscription ??= _pipEvents.receiveBroadcastStream().listen(
      (dynamic raw) {
        if (raw is! Map || raw['sessionId'] != _pipIdentity?['pipSessionId'])
          return;
        if (raw['type'] == 'stopped') {
          if (!(_pipStopped?.isCompleted ?? true)) _pipStopped!.complete();
          unawaited(_queue(_releasePictureInPicture));
        }
      },
      onError: (Object error, StackTrace stack) {
        developer.log(
          'PiP events failed',
          name: 'scene_compositor',
          error: error,
          stackTrace: stack,
        );
      },
    );
    final recorder = ui.PictureRecorder();
    ui.Canvas(
      recorder,
    ).drawColor(Color(_visual!.colors.first), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(8, 8);
    Uint8List poster;
    try {
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      poster = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
    } finally {
      image.dispose();
      picture.dispose();
    }
    final generation = _documentGeneration!;
    final identity = await _pipChannel
        .invokeMapMethod<Object?, Object?>('prepareWithSceneContinuation', {
          'sessionId': 'pip:$_sessionId',
          'sceneSessionId': _sessionId,
          'sceneSurfaceIdentity': {
            'generation': generation,
            'revision': 0,
            'semanticPlanHash': 'v1:$generation:0',
          },
          'sourceKind': 'sceneComposition',
          'posterBytes': poster,
          'width': 360,
          'height': (360 * _size.height / _size.width).round().clamp(1, 1280),
          'framesPerSecond': 30,
          'degradedFramesPerSecond': 15,
        })
        .timeout(const Duration(seconds: 12));
    if (identity == null)
      throw StateError('La escena todavía no está lista para PiP.');
    _pipIdentity = identity;
    _pipStopped = Completer<void>();
    try {
      if (await _pipChannel
              .invokeMethod<bool>('start')
              .timeout(const Duration(seconds: 12)) !=
          true) {
        throw StateError('iOS rechazó el inicio de PiP.');
      }
    } on Object {
      await _releasePictureInPicture();
      rethrow;
    }
    notifyListeners();
  });

  Future<void> stopPictureInPicture() => _queue(_stopPictureInPicture);
  Future<void> _stopPictureInPicture() async {
    if (_pipIdentity == null) return;
    await _pipChannel
        .invokeMethod<bool>('stop', {'reason': 'creator'})
        .timeout(const Duration(seconds: 8));
    await _pipStopped?.future.timeout(const Duration(seconds: 8));
    await _releasePictureInPicture();
  }

  Future<void> _releasePictureInPicture() async {
    final identity = _pipIdentity;
    if (identity == null) return;
    await _pipChannel
        .invokeMethod<Object>('releaseSceneContinuation', identity)
        .timeout(const Duration(seconds: 8));
    _pipIdentity = null;
    if (!_disposed) notifyListeners();
  }

  Future<void> _detach() async {
    await _stopPictureInPicture();
    final android = _android;
    if (android != null) {
      await android.close();
      _android = null;
      _preview = null;
    }
    if (_sessionId == null) return;
    await _invoke<Object>('detach', {'sessionId': _sessionId!});
    _sessionId = null;
    _documentGeneration = null;
    _textureId = null;
  }

  static void _validateViewport(Size size, double ratio) {
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.isEmpty ||
        size.width > 8192 ||
        size.height > 8192 ||
        !ratio.isFinite ||
        ratio <= 0 ||
        ratio > 8) {
      throw ArgumentError('Invalid compositor viewport.');
    }
  }

  Future<void> close() async {
    if (_closed) return;
    await _queue(() async {
      await _detach();
      await _pipSubscription?.cancel();
      _pipSubscription = null;
      _closed = true;
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (!_closed) {
      unawaited(
        close().catchError((Object error, StackTrace stack) {
          developer.log(
            'Compositor cleanup failed',
            name: 'scene_compositor',
            error: error,
            stackTrace: stack,
          );
        }),
      );
    }
    super.dispose();
  }
}
