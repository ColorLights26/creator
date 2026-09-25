import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'creator_visual_definition.dart';

/// Prepared resources and GPU Canvas replay for the portable native commands.
/// No renderer, shader or image is created per particle or per presentation.
class CreatorCommandCanvas {
  CreatorCommandCanvas._(this.visual);
  final CreatorVisualDefinition visual;
  final _images = <ui.Image>[];
  final _programs = <ui.FragmentProgram>[];
  final _materials = <Map<String, dynamic>>[];

  static Future<CreatorCommandCanvas> prepare(
    CreatorVisualDefinition visual,
  ) async {
    final result = CreatorCommandCanvas._(visual);
    try {
      final images = visual.images.keys.toList()..sort();
      final imageHashes = visual.nativeBuild['imageHashes'] as Map;
      var imageBytes = 0;
      for (final name in images) {
        final data = await rootBundle.load(
          'packages/visual_catalog/${visual.images[name]}',
        );
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        if (bytes.length > 16 * 1024 * 1024 ||
            sha256.convert(bytes).toString() != imageHashes[name]) {
          throw StateError(
            'Packaged image differs from compiled catalog: $name',
          );
        }
        final descriptorBuffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        ui.ImageDescriptor? descriptor;
        try {
          descriptor = await ui.ImageDescriptor.encoded(descriptorBuffer);
          imageBytes += descriptor.width * descriptor.height * 4;
          if (descriptor.width > 4096 ||
              descriptor.height > 4096 ||
              imageBytes > 64 * 1024 * 1024) {
            throw StateError('Session image budget exceeded: $name');
          }
        } finally {
          descriptor?.dispose();
          descriptorBuffer.dispose();
        }
        final codec = await ui.instantiateImageCodec(bytes);
        try {
          final frame = await codec.getNextFrame();
          if (frame.image.width * frame.image.height > 16777216) {
            frame.image.dispose();
            throw StateError('Image pixel budget exceeded: $name');
          }
          result._images.add(frame.image);
        } finally {
          codec.dispose();
        }
      }
      final map = Map<String, dynamic>.from(
        visual.nativeBuild['materials'] as Map,
      );
      final names = map.keys.toList()..sort();
      for (final name in names) {
        final material = Map<String, dynamic>.from(map[name] as Map);
        final binary = await rootBundle.load(material['asset'] as String);
        if (sha256
                .convert(
                  binary.buffer.asUint8List(
                    binary.offsetInBytes,
                    binary.lengthInBytes,
                  ),
                )
                .toString() !=
            material['assetHash']) {
          throw StateError(
            'Packaged material differs from compiled catalog: $name',
          );
        }
        result._materials.add(material);
        result._programs.add(
          await ui.FragmentProgram.fromAsset(material['asset'] as String),
        );
      }
      return result;
    } on Object {
      result.dispose();
      rethrow;
    }
  }

  /// Shader objects must remain alive through Picture.toImage. Each material
  /// draw has its own uniforms; reusing a mutable shader would alter earlier draws.
  List<ui.Shader> paint(ui.Canvas canvas, Float32List commands) {
    final shaders = <ui.Shader>[];
    final r = _CommandReader(commands, shaders);
    var depth = 0;
    try {
      while (!r.done) {
        final op = r.integer(1, 9), length = r.integer(0, 262144);
        final end = r.position + length;
        if (end > commands.length)
          throw const FormatException('Truncated native draw');
        switch (op) {
          case 1:
            canvas.save();
            depth++;
          case 2:
            if (depth-- <= 0)
              throw const FormatException('Native restore underflow');
            canvas.restore();
          case 3:
            final alpha = r.unit(), blend = _blend(r.integer(0, 2));
            canvas.saveLayer(
              null,
              ui.Paint()
                ..color = ui.Color.fromRGBO(255, 255, 255, alpha)
                ..blendMode = blend,
            );
            depth++;
          case 4:
            final a = r.value(),
                b = r.value(),
                c = r.value(),
                d = r.value(),
                x = r.value(),
                y = r.value();
            canvas.transform(
              Float64List.fromList([
                a,
                b,
                0,
                0,
                c,
                d,
                0,
                0,
                0,
                0,
                1,
                0,
                x,
                y,
                0,
                1,
              ]),
            );
          case 5:
            canvas.clipPath(r.path());
          case 6:
            final paint = r.paint();
            canvas.drawPath(r.path(), paint);
          case 7:
            final paint = r.paint(),
                radius = r.value(),
                count = r.integer(0, 32768);
            final positions = Float32List(count * 2);
            for (var j = 0; j < positions.length; j++) positions[j] = r.value();
            paint
              ..strokeWidth = radius * 2
              ..strokeCap = ui.StrokeCap.round;
            canvas.drawRawPoints(ui.PointMode.points, positions, paint);
          case 8:
            final image = _images[r.integer(0, _images.length - 1)],
                rect = r.rect();
            final paint =
                ui.Paint()
                  ..color = ui.Color.fromRGBO(255, 255, 255, r.unit())
                  ..blendMode = _blend(r.integer(0, 2));
            canvas.drawImageRect(
              image,
              ui.Rect.fromLTWH(
                0,
                0,
                image.width.toDouble(),
                image.height.toDouble(),
              ),
              rect,
              paint,
            );
          case 9:
            final index = r.integer(0, _programs.length - 1),
                rect = r.rect(),
                blend = _blend(r.integer(0, 2));
            final count = r.integer(0, 1024),
                values = <double>[rect.width, rect.height];
            for (var j = 0; j < count; j++) values.add(r.value());
            final textures = <int>[], textureCount = r.integer(0, 16);
            for (var j = 0; j < textureCount; j++)
              textures.add(r.integer(0, _images.length - 1));
            final definition = _materials[index];
            if (values.length != definition['floatCount'] ||
                textures.length != definition['samplerCount'])
              throw StateError(
                'Material uniforms/samplers do not match compiled source.',
              );
            final shader = _programs[index].fragmentShader();
            shaders.add(shader);
            for (var j = 0; j < values.length; j++)
              shader.setFloat(j, values[j]);
            for (var j = 0; j < textures.length; j++)
              shader.setImageSampler(j, _images[textures[j]]);
            canvas.save();
            canvas.translate(rect.left, rect.top);
            canvas.drawRect(
              ui.Offset.zero & rect.size,
              ui.Paint()
                ..shader = shader
                ..blendMode = blend,
            );
            canvas.restore();
        }
        if (r.position != end || depth > 64)
          throw const FormatException('Native draw layout/stack mismatch');
      }
      if (depth != 0)
        throw const FormatException('Native drawing stack not closed');
      return shaders;
    } on Object {
      for (final shader in shaders) shader.dispose();
      rethrow;
    }
  }

  void dispose() {
    for (final image in _images) image.dispose();
    _images.clear();
    _programs.clear();
  }
}

ui.BlendMode _blend(int index) =>
    [ui.BlendMode.srcOver, ui.BlendMode.plus, ui.BlendMode.screen][index];

class _CommandReader {
  _CommandReader(this.data, this.shaders);
  final Float32List data;
  final List<ui.Shader> shaders;
  int position = 0;
  bool get done => position == data.length;
  double value() {
    if (position >= data.length)
      throw const FormatException('Truncated native field');
    final v = data[position++];
    if (!v.isFinite) throw const FormatException('Non-finite native field');
    return v;
  }

  int integer(int lo, int hi) {
    final v = value();
    if (v != v.truncateToDouble() || v < lo || v > hi)
      throw const FormatException('Invalid native index');
    return v.toInt();
  }

  double unit() {
    final v = value();
    if (v < 0 || v > 1) throw const FormatException('Invalid native color');
    return v;
  }

  ui.Color color() => ui.Color.from(
    alpha: 1,
    red: 0,
    green: 0,
    blue: 0,
  ).withValues(red: unit(), green: unit(), blue: unit(), alpha: unit());
  ui.Rect rect() => ui.Rect.fromLTWH(value(), value(), value(), value());
  ui.Path path() {
    final result =
        ui.Path()
          ..fillType =
              integer(0, 1) == 0
                  ? ui.PathFillType.nonZero
                  : ui.PathFillType.evenOdd;
    final end = position + 1 + integer(0, 262144);
    if (end > data.length) throw const FormatException('Truncated path');
    while (position < end) {
      switch (integer(0, 4)) {
        case 0:
          result.moveTo(value(), value());
        case 1:
          result.lineTo(value(), value());
        case 2:
          result.quadraticBezierTo(value(), value(), value(), value());
        case 3:
          result.cubicTo(value(), value(), value(), value(), value(), value());
        case 4:
          result.close();
      }
    }
    if (position != end) throw const FormatException('Invalid path length');
    return result;
  }

  ui.Paint paint() {
    final p =
        ui.Paint()
          ..color = color()
          ..blendMode = _blend(integer(0, 2));
    final stroke = value();
    p
      ..style = stroke == 0 ? ui.PaintingStyle.fill : ui.PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = ui.StrokeCap.values[integer(0, 2)]
      ..strokeJoin = ui.StrokeJoin.values[integer(0, 2)];
    final gradient = integer(0, 2),
        a = ui.Offset(value(), value()),
        b = ui.Offset(value(), value()),
        count = integer(0, 8);
    final colors = <ui.Color>[], stops = <double>[];
    for (var i = 0; i < count; i++) {
      colors.add(color());
      stops.add(unit());
    }
    if (gradient == 1) p.shader = ui.Gradient.linear(a, b, colors, stops);
    if (gradient == 2) p.shader = ui.Gradient.radial(a, b.dx, colors, stops);
    if (p.shader != null) shaders.add(p.shader!);
    return p;
  }
}
