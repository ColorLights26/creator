import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'adjustment_session.dart';
import 'modifier_row.dart';
import 'palettes.dart';

/// The visual's own colors · curated palettes · Armónica. A tap recolors the
/// visual live without restarting it.
class PaletteRow extends StatelessWidget {
  const PaletteRow({required this.session, super.key});

  final AdjustmentSession session;

  @override
  Widget build(BuildContext context) {
    final visual = session.visual;
    void pick(List<int>? colors) {
      if (listEquals(colors, session.palette)) return;
      HapticFeedback.selectionClick();
      session.setPalette(colors);
    }

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _Swatch(
            key: const ValueKey('adjustments-palette-original'),
            label: 'Sus colores',
            colors: visual.colors,
            selected: session.palette == null,
            onTap: () => pick(null),
          ),
          for (final palette in studioPalettes)
            _Swatch(
              key: ValueKey('adjustments-palette-${palette.name}'),
              label: palette.name,
              colors: palette.colors,
              selected: listEquals(
                session.palette,
                paletteFor(visual, palette.colors),
              ),
              onTap: () => pick(paletteFor(visual, palette.colors)),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              key: const ValueKey('adjustments-palette-harmonic'),
              tooltip: 'Sus colores en otro tono',
              avatar: const Icon(
                Icons.palette_outlined,
                size: 18,
                color: adjustmentsAccent,
              ),
              label: const Text('Armónica'),
              onPressed: () => pick(harmonicPalette(visual, math.Random())),
            ),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.label,
    required this.colors,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final List<int> colors;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Color(colors.first).withAlpha(255),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: selected ? adjustmentsAccent : Colors.white24,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final color in colors.skip(1))
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: Color(color).withAlpha(255),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
