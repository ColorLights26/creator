import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:scene_compositor/scene_compositor.dart';

/// Curated palettes for the palette row: background first, then the three
/// accents, like a visual's metadata colors.
const studioPalettes = [
  (name: 'Océano', colors: [0xff03111f, 0xff1fb6ff, 0xff2de2c4, 0xffa7f3ff]),
  (name: 'Atardecer', colors: [0xff1a0b16, 0xffff7a45, 0xffff4f8b, 0xffffd166]),
  (name: 'Neón', colors: [0xff07021a, 0xffff2bd6, 0xff2bffea, 0xff8a5cff]),
  (name: 'Bosque', colors: [0xff041208, 0xff3ddc84, 0xffb8f15b, 0xfff4ffb0]),
  (name: 'Lava', colors: [0xff140301, 0xffff3d00, 0xffffa000, 0xffffe082]),
  (name: 'Hielo', colors: [0xff050b14, 0xff9bd7ff, 0xffe0f7ff, 0xff6aa8ff]),
  (name: 'Oro', colors: [0xff120c02, 0xffffc94a, 0xffffe7a3, 0xffb8862b]),
  (name: 'Rosa', colors: [0xff16060f, 0xffff8fc7, 0xffffc2e2, 0xffc77dff]),
];

/// Whether a palette can recolor [visual] live: native code that reads its
/// colors.
bool usesPalette(CreatorVisualDefinition visual) =>
    visual.isNative && RegExp(r'\.colors\b').hasMatch(visual.nativeSource);

/// [colors] adapted to [visual]: an overlay keeps its own first color, which
/// is its transparency, so a palette never paints over the app behind it.
List<int> paletteFor(CreatorVisualDefinition visual, List<int> colors) => [
  visual.role == CreatorRole.overlay ? visual.colors.first : colors.first,
  ...colors.skip(1),
];

/// The visual's own colors with their hue turned, keeping light and
/// saturation: the same mood in another key.
List<int> harmonicPalette(CreatorVisualDefinition visual, math.Random random) {
  final turn = 60 + random.nextDouble() * 240;
  return paletteFor(visual, [
    for (final value in visual.colors)
      () {
        final color = HSLColor.fromColor(Color(value));
        return color.withHue((color.hue + turn) % 360).toColor().toARGB32();
      }(),
  ]);
}
