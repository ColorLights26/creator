import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:visual_contract/visual_contract.dart';

import 'cpu_clock.dart';
import 'creator_shader_frame.dart';
import 'creator_native_program.dart';
import 'creator_command_canvas.dart';
import 'creator_visual_definition.dart';
import 'creator_shader_program.dart';

/// Cumulative cost of the frames an [AndroidCreatorSession] presented while
/// [AndroidCreatorSession.measureCost] was on, for diagnostics overlays.
/// Readers take deltas between two snapshots of the same [sessionId]; a new
/// session starts again from zero.
@immutable
class AndroidCreatorRenderStats {
  const AndroidCreatorRenderStats({
    required this.sessionId,
    required this.frames,
    required this.cpuMicros,
    required this.simulationMicros,
  });

  final int sessionId;

  /// Frames actually presented (discarded ones are not counted).
  final int frames;

  /// CPU time of the Dart thread recording those frames: native simulation
  /// and draw commands or shader uniforms, plus Canvas recording. Raster and
  /// GPU work happen elsewhere. Null when the CPU clock is unavailable.
  final int? cpuMicros;

  /// Wall time of the native simulation step (`cp_update`) alone.
  final double simulationMicros;
}

/// The Android Flutter shader backend is reusable by the production Flutter
/// compositor. It never opens audio and never accesses application services.
class AndroidCreatorSession extends ChangeNotifier {
  AndroidCreatorSession._({
    required this.visual,
    required this.visualIndex,
    required ui.FragmentShader? shader,
    CreatorNativeProgram? native,
    CreatorCommandCanvas? canvas,
    required Size size,
    required double pixelRatio,
    required bool reactive,
    required bool playing,
    required this.onError,
  }) : _shader = shader,
       _native = native,
       _canvas = canvas,
       _reactive = reactive,
       _size = size,
       _pixelRatio = pixelRatio,
       _state = CreatorShaderFrame(
         visual: visual,
         visualIndex: visualIndex,
         reactive: reactive,
       ) {
    _state.setPlaying(playing, hostTime: 0);
    _native?.configure(reactive: reactive, playing: playing, hostTime: 0);
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
    if (visual.isNative) {
      final canvas = await CreatorCommandCanvas.prepare(visual);
      CreatorNativeProgram? native;
      try {
        native = CreatorNativeProgram(visual);
        return AndroidCreatorSession._(
          visual: visual,
          visualIndex: visualIndex,
          shader: null,
          native: native,
          canvas: canvas,
          size: size,
          pixelRatio: pixelRatio,
          reactive: reactive,
          playing: playing,
          onError: onError,
        );
      } on Object {
        native?.dispose();
        canvas.dispose();
        rethrow;
      }
    }
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
  final ui.FragmentShader? _shader;
  final CreatorNativeProgram? _native;
  final CreatorCommandCanvas? _canvas;
  bool _reactive;
  final void Function(Object, StackTrace) onError;
  final ChangeNotifier repaint = ChangeNotifier();
  CreatorShaderFrame _state;
  Size _size;
  double _pixelRatio;
  double _hostTime = 0;

  /// The background fill follows a live palette.
  late int _background = visual.colors.first;
  ui.Image? _image;
  Future<void>? _inFlight;
  int _generation = 0;
  int _renderedGeneration = -1;
  bool _closed = false;
  bool _failed = false;
  static int _nextSessionId = 0;
  final int _sessionId = _nextSessionId++;
  int _statFrames = 0;
  int _statCpuMicros = 0;
  double _statSimulationMicros = 0;

  /// Accumulates [stats] for every presented frame. Off by default: apps that
  /// embed the renderer pay nothing; a diagnostics overlay turns it on.
  bool measureCost = false;

  ui.Image? get image => _image;

  AndroidCreatorRenderStats get stats => AndroidCreatorRenderStats(
    sessionId: _sessionId,
    frames: _statFrames,
    cpuMicros: CpuClock.instance == null ? null : _statCpuMicros,
    simulationMicros: _statSimulationMicros,
  );
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
    _native?.configure(
      reactive: _reactive,
      playing: playing,
      hostTime: _hostTime,
    );
    notifyListeners();
  }

  void setReactive(bool reactive) {
    if (_closed || _reactive == reactive) return;
    _state.setReactive(reactive);
    _reactive = reactive;
    _native?.configure(
      reactive: reactive,
      playing: _state.playing,
      hostTime: _hostTime,
    );
    _generation++;
    notifyListeners();
  }

  void setControls(CreatorControls controls) {
    if (_closed) return;
    controls.validate();
    _state.setControls(controls);
    _native?.setControls(controls);
    _native?.configure(
      reactive: _reactive,
      playing: _state.playing,
      hostTime: _hostTime,
    );
    _generation++;
    notifyListeners();
  }

  /// Live modifier change. While playing the next frame picks it up; a
  /// paused surface redraws once. Restarting would lose the simulation.
  void setModifiers(Map<String, double> values) {
    if (_closed || _native == null) return;
    _native.setModifiers(values);
    _native.configure(
      reactive: _reactive,
      playing: _state.playing,
      hostTime: _hostTime,
    );
    if (!_state.playing) _generation++;
    notifyListeners();
  }

  /// Live palette: the program and the background fill take [colors] (four
  /// ARGB) without restarting; a paused surface redraws once.
  void setColors(List<int> colors) {
    if (_closed || _native == null) return;
    _native.setColors(colors);
    _native.configure(
      reactive: _reactive,
      playing: _state.playing,
      hostTime: _hostTime,
    );
    _background = colors.first;
    if (!_state.playing) _generation++;
    notifyListeners();
  }

  void reset({required bool reactive, int? seed}) {
    if (_closed) return;
    final wasPlaying = _state.playing;
    final controls = _state.controls;
    _reactive = reactive;
    _native?.reset(seed: seed);
    _native?.configure(
      reactive: reactive,
      playing: wasPlaying,
      hostTime: _hostTime,
    );
    _state = CreatorShaderFrame(
      visual: visual,
      visualIndex: visualIndex,
      reactive: reactive,
      seed: seed,
    )..setPlaying(wasPlaying, hostTime: _hostTime);
    _state.setControls(controls);
    _failed = false;
    _generation++;
    notifyListeners();
  }

  void consume(SceneRenderSignalFrameV2 frame) {
    if (!_closed) {
      _state.consume(frame);
      _native?.consume(frame);
    }
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
    var materialShaders = <ui.Shader>[];
    final measure = measureCost;
    final clock = measure ? CpuClock.instance : null;
    final cpuStart = clock?.threadMicros;
    var simulationMicros = 0.0;
    try {
      final size = rasterSize(_size, _pixelRatio);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      if (visual.role == CreatorRole.background) {
        canvas.drawColor(
          Color(_background).withAlpha(255),
          BlendMode.src,
        );
      }
      if (_native case final native?) {
        native.configure(
          reactive: _reactive,
          playing: _state.playing,
          hostTime: _hostTime,
        );
        native.update(
          width: _size.width,
          height: _size.height,
          hostTime: _hostTime,
          reducedMotion: reducedMotion,
        );
        if (measure) simulationMicros = native.updateMicros;
        canvas.scale(size.width / _size.width, size.height / _size.height);
        materialShaders = _canvas!.paint(canvas, native.draw());
      } else {
        final uniforms = _state.uniforms(
          width: size.width,
          height: size.height,
          hostTime: _hostTime,
          reducedMotion: reducedMotion,
        );
        for (var i = 0; i < uniforms.length; i++)
          _shader!.setFloat(i, uniforms[i]);
        canvas.drawRect(Offset.zero & size, ui.Paint()..shader = _shader);
      }
      picture = recorder.endRecording();
      final cpuEnd = clock?.threadMicros;
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
      if (measure) {
        _statFrames++;
        _statSimulationMicros += simulationMicros;
        if (cpuStart != null && cpuEnd != null && cpuEnd >= cpuStart) {
          _statCpuMicros += cpuEnd - cpuStart;
        }
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
      for (final shader in materialShaders) shader.dispose();
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
    _shader?.dispose();
    _native?.dispose();
    _canvas?.dispose();
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
    if (_hostMicros - _lastRenderMicros <
        (1000000 / widget.session.visual.framesPerSecond).round())
      return;
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
