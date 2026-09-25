import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

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
  Size _size = Size.zero;
  double _pixelRatio = 1;
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
    final installedVisuals = (catalog['visuals'] as List)
        .cast<Map<String, dynamic>>();
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
    _reactive = reactive;
    if (_android != null) {
      _android!.reset(reactive: reactive, seed: _qaSeed);
      return;
    }
    await _detach();
    await _attach();
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
        ),
      });
      final texture = receipt?['textureId'];
      if (texture is! int || texture < 0)
        throw StateError('El compositor no devolvió una textura válida.');
      _textureId = texture;
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

  Future<void> _detach() async {
    final android = _android;
    if (android != null) {
      await android.close();
      _android = null;
      _preview = null;
    }
    if (_sessionId == null) return;
    await _invoke<Object>('detach', {'sessionId': _sessionId!});
    _sessionId = null;
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
