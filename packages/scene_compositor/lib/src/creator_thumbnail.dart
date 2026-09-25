import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:visual_contract/visual_contract.dart';

import 'creator_shader_frame.dart';
import 'creator_native_program.dart';
import 'creator_command_canvas.dart';
import 'creator_shader_program.dart';
import 'creator_visual_definition.dart';

/// A frozen, cached frame. Catalog grids never start a compositor or a ticker.
class CreatorThumbnail extends StatefulWidget {
  const CreatorThumbnail({
    super.key,
    required this.visual,
    required this.visualIndex,
    required this.assets,
    this.timeSeconds,
  });

  final CreatorVisualDefinition visual;
  final int visualIndex;
  final CreatorCatalogAssets assets;
  final double? timeSeconds;

  @override
  State<CreatorThumbnail> createState() => _CreatorThumbnailState();
}

class _CreatorThumbnailState extends State<CreatorThumbnail> {
  Future<Uint8List>? _poster;
  String? _key;

  @override
  void initState() {
    super.initState();
    _update();
  }

  @override
  void didUpdateWidget(CreatorThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  void _update() {
    if (widget.visual.thumbnail.assetPath != null) return;
    final time = widget.timeSeconds ?? widget.visual.thumbnail.timeSeconds;
    final key = jsonEncode([
      widget.assets.shaderAsset,
      widget.visualIndex,
      widget.visual.toManifest(),
      time,
    ]);
    if (key == _key) return;
    _key = key;
    _poster = _FrozenPosters.load(
      key,
      visual: widget.visual,
      index: widget.visualIndex,
      shaderAsset: widget.assets.shaderAsset,
      time: time,
    );
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.visual.thumbnail;
    final asset = spec.assetPath;
    if (asset != null) {
      final package = spec.assetPackage ?? widget.assets.assetPackage;
      return Image.asset(asset, package: package, fit: BoxFit.cover);
    }
    return FutureBuilder<Uint8List>(
      future: _poster,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null) {
          return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
        }
        return Semantics(
          label: snapshot.hasError
              ? 'Miniatura no disponible'
              : widget.visual.name,
          child: ColoredBox(color: Color(widget.visual.colors.first)),
        );
      },
    );
  }
}

class _FrozenPosters {
  static final _cache = LinkedHashMap<String, Future<Uint8List>>();
  static Future<void> _pending = Future.value();
  static final _demo = createSyntheticSceneSignalRecording();

  static Future<Uint8List> load(
    String key, {
    required CreatorVisualDefinition visual,
    required int index,
    required String shaderAsset,
    required double time,
  }) {
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }
    // Only one 256px raster/readback at a time; at most 64 compressed posters.
    final next = _pending.then(
      (_) => _render(visual, index, shaderAsset, time),
    );
    _pending = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        _cache.remove(key);
        developer.log(
          'Frozen visual thumbnail failed',
          name: 'scene_compositor',
          error: error,
          stackTrace: stack,
        );
      },
    );
    _cache[key] = next;
    while (_cache.length > 64) {
      _cache.remove(_cache.keys.first);
    }
    return next;
  }

  static Future<Uint8List> _render(
    CreatorVisualDefinition visual,
    int index,
    String asset,
    double time,
  ) async {
    if (!time.isFinite || time < 0 || time > 3600) {
      throw ArgumentError('Invalid thumbnail time.');
    }
    if (visual.isNative) return _renderNative(visual, time);
    final program = await loadCreatorShaderProgram(asset);
    final shader = program.fragmentShader();
    ui.Picture? picture;
    ui.Image? image;
    try {
      final state = CreatorShaderFrame(
        visual: visual,
        visualIndex: index,
        reactive: visual.reactivity != CreatorReactivity.none,
      );
      final sampleTime =
          (time * 1000000).round() % _demo.duration.inMicroseconds;
      final sample = _demo.samples.lastWhere(
        (sample) => sample.hostTime.inMicroseconds <= sampleTime,
        orElse: () => _demo.samples.first,
      );
      state.consume(sample.frame);
      final uniforms = state.uniforms(
        width: 256,
        height: 256,
        hostTime: 0,
        reducedMotion: false,
      );
      uniforms[2] = time;
      for (var i = 0; i < uniforms.length; i++) {
        shader.setFloat(i, uniforms[i]);
      }
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 256, 256),
        ui.Paint()..shader = shader,
      );
      picture = recorder.endRecording();
      image = await picture.toImage(256, 256);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Unable to encode visual thumbnail.');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image?.dispose();
      picture?.dispose();
      shader.dispose();
    }
  }
  static Future<Uint8List> _renderNative(CreatorVisualDefinition visual, double time) async {
    // FFI state is created and destroyed inside the worker. Only value commands
    // cross isolates; the live scene and its native pointers are never touched.
    final commands = await Isolate.run(() => _replayNative(visual, time));
    final resources = await CreatorCommandCanvas.prepare(visual);
    ui.Picture? picture;
    ui.Image? image;
    var shaders = <ui.Shader>[];
    try {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      if (visual.role == CreatorRole.background) canvas.drawColor(Color(visual.colors.first).withAlpha(255), BlendMode.src);
      shaders = resources.paint(canvas, commands);
      picture = recorder.endRecording();
      image = await picture.toImage(256, 256);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Unable to encode native thumbnail.');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image?.dispose(); picture?.dispose();
      for (final shader in shaders) shader.dispose();
      resources.dispose();
    }
  }

  static Float32List _replayNative(CreatorVisualDefinition visual, double time) {
    final program = CreatorNativeProgram(visual);
    final replay = SceneSignalReplay(createSyntheticSceneSignalRecording());
    try {
      program.configure(reactive: visual.reactivity != CreatorReactivity.none, playing: true, hostTime: 0);
      final steps = (time * visual.framesPerSecond).ceil();
      for (var i=0; i<=steps; i++) {
        final position = (i / visual.framesPerSecond).clamp(0.0, time);
        final batch = replay.advance(Duration(microseconds: (position * 1000000).round()));
        if (batch.resetRequired) program.reset();
        for (final sample in batch.samples) program.consume(sample.frame);
        program.update(width: 256, height: 256, hostTime: position, reducedMotion: false);
      }
      return Float32List.fromList(program.draw());
    } finally { program.dispose(); }
  }

}
