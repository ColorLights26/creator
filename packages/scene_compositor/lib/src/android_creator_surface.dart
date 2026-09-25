import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:visual_contract/visual_contract.dart';

import 'creator_shader_frame.dart';
import 'creator_visual_definition.dart';
import 'creator_shader_program.dart';

/// The Android Flutter shader backend is reusable by the production Flutter
/// compositor. It never opens audio and never accesses application services.
class AndroidCreatorSession extends ChangeNotifier {
  AndroidCreatorSession._({
    required this.visual,
    required this.visualIndex,
    required ui.FragmentShader shader,
    required Size size,
    required double pixelRatio,
    required bool reactive,
    required bool playing,
    required this.onError,
  }) : _shader = shader,
       _size = size,
       _pixelRatio = pixelRatio,
       _state = CreatorShaderFrame(
         visual: visual,
         visualIndex: visualIndex,
         reactive: reactive,
       ) {
    _state.setPlaying(playing, hostTime: 0);
  }

  static Future<AndroidCreatorSession> create({
    String shaderAsset = 'shaders/creator_programs.frag',
    required CreatorVisualDefinition visual,
    required int visualIndex,
    required Size size,
    required double pixelRatio,
    required bool reactive,
    required bool playing,
    required void Function(Object, StackTrace) onError,
  }) async {
    final program = await loadCreatorShaderProgram(shaderAsset);
    return AndroidCreatorSession._(
      visual: visual,
      visualIndex: visualIndex,
      shader: program.fragmentShader(),
      size: size,
      pixelRatio: pixelRatio,
      reactive: reactive,
      playing: playing,
      onError: onError,
    );
  }

  final CreatorVisualDefinition visual;
  final int visualIndex;
  final ui.FragmentShader _shader;
  final void Function(Object, StackTrace) onError;
  final ChangeNotifier repaint = ChangeNotifier();
  CreatorShaderFrame _state;
  Size _size;
  double _pixelRatio;
  double _hostTime = 0;
  ui.Image? _image;
  Future<void>? _inFlight;
  int _generation = 0;
  int _renderedGeneration = -1;
  bool _closed = false;
  bool _failed = false;

  ui.Image? get image => _image;
  bool get playing => !_closed && !_failed && _state.playing;
  bool get closed => _closed;

  /// Actual offscreen raster dimensions, not merely a logical Canvas scale.
  static Size rasterSize(Size logicalSize, double pixelRatio) {
    if (!logicalSize.width.isFinite ||
        !logicalSize.height.isFinite ||
        logicalSize.isEmpty ||
        !pixelRatio.isFinite ||
        pixelRatio <= 0) {
      throw ArgumentError('Invalid raster viewport.');
    }
    final width = logicalSize.width * pixelRatio;
    final height = logicalSize.height * pixelRatio;
    final scale = math.min(1.0, 1024 / math.max(width, height));
    return Size(
      (width * scale).round().clamp(1, 1024).toDouble(),
      (height * scale).round().clamp(1, 1024).toDouble(),
    );
  }

  void resize(Size size, double pixelRatio) {
    if (_closed) return;
    _size = size;
    _pixelRatio = pixelRatio;
    _generation++;
    notifyListeners();
  }

  void setPlaying(bool playing) {
    if (_closed) return;
    _state.setPlaying(playing, hostTime: _hostTime);
    notifyListeners();
  }

  void reset({required bool reactive, int? seed}) {
    if (_closed) return;
    final wasPlaying = _state.playing;
    _state = CreatorShaderFrame(
      visual: visual,
      visualIndex: visualIndex,
      reactive: reactive,
      seed: seed,
    )..setPlaying(wasPlaying, hostTime: _hostTime);
    _failed = false;
    _generation++;
    notifyListeners();
  }

  void consume(SceneRenderSignalFrameV2 frame) {
    if (!_closed) _state.consume(frame);
  }

  void render(double hostTime, {required bool reducedMotion}) {
    if (_closed || _failed || _inFlight != null) return;
    // Pausing keeps the presented image. An explicit reset or viewport change
    // can still request one frame without starting another ticker.
    if (!_state.playing && _image != null && _renderedGeneration == _generation)
      return;
    _hostTime = hostTime;
    final generation = _generation;
    _inFlight = _render(generation, reducedMotion).whenComplete(() {
      _inFlight = null;
      if (!_closed && generation != _generation) notifyListeners();
    });
  }

  Future<void> _render(int generation, bool reducedMotion) async {
    ui.Picture? picture;
    try {
      final size = rasterSize(_size, _pixelRatio);
      final uniforms = _state.uniforms(
        width: size.width,
        height: size.height,
        hostTime: _hostTime,
        reducedMotion: reducedMotion,
      );
      for (var i = 0; i < uniforms.length; i++) {
        _shader.setFloat(i, uniforms[i]);
      }
      final recorder = ui.PictureRecorder();
      ui.Canvas(
        recorder,
      ).drawRect(Offset.zero & size, ui.Paint()..shader = _shader);
      picture = recorder.endRecording();
      // One pending image plus the displayed image bounds the owned targets.
      // With a GPU context the image remains GPU-resident; no toByteData/readback.
      final next = await picture.toImage(
        size.width.toInt(),
        size.height.toInt(),
      );
      if (_closed || generation != _generation) {
        next.dispose();
        return;
      }
      final previous = _image;
      _image = next;
      _renderedGeneration = generation;
      repaint.notifyListeners();
      previous?.dispose();
    } on Object catch (error, stack) {
      if (!_closed) {
        _failed = true;
        notifyListeners();
        onError(error, stack);
      }
    } finally {
      picture?.dispose();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _generation++;
    notifyListeners();
    await _inFlight;
    _image?.dispose();
    _image = null;
    _shader.dispose();
    repaint.dispose();
    super.dispose();
  }
}

/// Owns the Android renderer's only ticker. The studio drives playback and
/// lifecycle; this surface additionally respects TickerMode and Reduce Motion.
class AndroidCreatorPreview extends StatefulWidget {
  const AndroidCreatorPreview({super.key, required this.session});
  final AndroidCreatorSession session;

  @override
  State<AndroidCreatorPreview> createState() => _AndroidCreatorPreviewState();
}

class _AndroidCreatorPreviewState extends State<AndroidCreatorPreview>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  var _hostMicros = 0;
  var _lastTickMicros = 0;
  var _lastRenderMicros = -33334;
  var _renderScheduled = false;
  var _tickerMode = true;
  var _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    widget.session.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Keep the SDK's Flutter 3.29 minimum; valuesOf was added later.
    // ignore: deprecated_member_use
    _tickerMode = TickerMode.of(context);
    _reducedMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _changed();
  }

  @override
  void didUpdateWidget(AndroidCreatorPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session == widget.session) return;
    oldWidget.session.removeListener(_changed);
    widget.session.addListener(_changed);
    _changed();
  }

  void _changed() {
    if (!mounted) return;
    final active = widget.session.playing && _tickerMode;
    if (active && !_ticker.isActive) {
      _lastTickMicros = 0;
      _ticker.start();
    } else if (!active && _ticker.isActive) {
      _ticker.stop();
    }
    if (_renderScheduled || widget.session.closed || !_tickerMode) return;
    _renderScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _renderScheduled = false;
      if (!mounted || widget.session.closed) return;
      widget.session.render(
        _hostMicros / 1000000,
        reducedMotion: _reducedMotion,
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _tick(Duration elapsed) {
    final micros = elapsed.inMicroseconds;
    _hostMicros += math.max(0, micros - _lastTickMicros);
    _lastTickMicros = micros;
    if (_hostMicros - _lastRenderMicros < 33333) return;
    _lastRenderMicros = _hostMicros;
    widget.session.render(_hostMicros / 1000000, reducedMotion: _reducedMotion);
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _ImagePainter(widget.session),
      size: Size.infinite,
    ),
  );

  @override
  void dispose() {
    widget.session.removeListener(_changed);
    _ticker.dispose();
    super.dispose();
  }
}

class _ImagePainter extends CustomPainter {
  _ImagePainter(this.session) : super(repaint: session.repaint);
  final AndroidCreatorSession session;
  final ui.Paint _paint = ui.Paint()..filterQuality = ui.FilterQuality.low;

  @override
  void paint(Canvas canvas, Size size) {
    final image = session.image;
    if (image == null || size.isEmpty) return;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      _paint,
    );
  }

  @override
  bool shouldRepaint(_ImagePainter oldDelegate) =>
      oldDelegate.session != session;
}
