import 'package:flutter/material.dart';

const _accent = Color(0xFF73F572);
const _lightSurface = Color(0xFFF2F2F7);

/// Base surface behind every visual.
enum StudioBackgroundMode { dark, checkerboard, light }

/// A catalog background offered as a still frame behind overlays.
typedef StudioBackdropVisual = ({String id, String name, Widget thumbnail});

/// What the studio paints behind the visual. Only overlays let it through,
/// so it is how a transparent effect is judged over different scenes.
@immutable
class StudioBackdrop {
  const StudioBackdrop({
    required this.id,
    required this.label,
    this.base = StudioBackgroundMode.dark,
    this.colors = const [],
    this.visualId,
  });

  /// A catalog background, frozen at its thumbnail frame.
  factory StudioBackdrop.visual(StudioBackdropVisual visual) => StudioBackdrop(
    id: 'visual:${visual.id}',
    label: visual.name,
    visualId: visual.id,
  );

  final String id;
  final String label;

  /// Dark, light or the alpha grid, under everything else.
  final StudioBackgroundMode base;

  /// One color fills the surface; more paint a diagonal gradient.
  final List<Color> colors;

  /// The catalog background frozen behind the overlay.
  final String? visualId;

  static const alpha = StudioBackdrop(
    id: 'alpha',
    label: 'Cuadrícula alpha',
    base: StudioBackgroundMode.checkerboard,
  );
  static const dark = StudioBackdrop(id: 'oscuro', label: 'Oscuro');
  static const light = StudioBackdrop(
    id: 'claro',
    label: 'Claro',
    base: StudioBackgroundMode.light,
  );

  @override
  bool operator ==(Object other) => other is StudioBackdrop && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

const studioBasicBackdrops = [
  StudioBackdrop.alpha,
  StudioBackdrop.dark,
  StudioBackdrop.light,
];

/// Plain colors: contrast checks (does the effect vanish on white? on red?).
const studioColorBackdrops = [
  StudioBackdrop(id: 'negro', label: 'Negro', colors: [Color(0xFF000000)]),
  StudioBackdrop(id: 'gris', label: 'Gris', colors: [Color(0xFF5A5A60)]),
  StudioBackdrop(id: 'blanco', label: 'Blanco', colors: [Color(0xFFFFFFFF)]),
  StudioBackdrop(id: 'rojo', label: 'Rojo', colors: [Color(0xFFC62828)]),
  StudioBackdrop(id: 'naranja', label: 'Naranja', colors: [Color(0xFFEF6C00)]),
  StudioBackdrop(
    id: 'amarillo',
    label: 'Amarillo',
    colors: [Color(0xFFF9C80E)],
  ),
  StudioBackdrop(id: 'verde', label: 'Verde', colors: [Color(0xFF2E7D32)]),
  StudioBackdrop(
    id: 'turquesa',
    label: 'Turquesa',
    colors: [Color(0xFF00897B)],
  ),
  StudioBackdrop(id: 'azul', label: 'Azul', colors: [Color(0xFF1E40AF)]),
  StudioBackdrop(id: 'morado', label: 'Morado', colors: [Color(0xFF6A1B9A)]),
  StudioBackdrop(id: 'rosa', label: 'Rosa', colors: [Color(0xFFD81B60)]),
];

const studioGradientBackdrops = [
  StudioBackdrop(
    id: 'atardecer',
    label: 'Atardecer',
    colors: [Color(0xFFFF7E5F), Color(0xFF6A3093)],
  ),
  StudioBackdrop(
    id: 'oceano',
    label: 'Océano',
    colors: [Color(0xFF00C6FF), Color(0xFF0040A8)],
  ),
  StudioBackdrop(
    id: 'noche',
    label: 'Noche',
    colors: [Color(0xFF0F2027), Color(0xFF2C5364)],
  ),
  StudioBackdrop(
    id: 'neon',
    label: 'Neón',
    colors: [Color(0xFFFC466B), Color(0xFF3F5EFB)],
  ),
  StudioBackdrop(
    id: 'bosque',
    label: 'Bosque',
    colors: [Color(0xFF0B3D2E), Color(0xFF71B280)],
  ),
  StudioBackdrop(
    id: 'fuego',
    label: 'Fuego',
    colors: [Color(0xFFF12711), Color(0xFFF5AF19)],
  ),
  StudioBackdrop(
    id: 'menta',
    label: 'Menta',
    colors: [Color(0xFF00F260), Color(0xFF0575E6)],
  ),
  StudioBackdrop(
    id: 'lavanda',
    label: 'Lavanda',
    colors: [Color(0xFFC471F5), Color(0xFFFA71CD)],
  ),
  StudioBackdrop(
    id: 'arcoiris',
    label: 'Arcoíris',
    colors: [
      Color(0xFFFF2D2D),
      Color(0xFFFF9F1C),
      Color(0xFFFFE600),
      Color(0xFF2ECC40),
      Color(0xFF1E90FF),
      Color(0xFF8E44FF),
    ],
  ),
];

/// The color, gradient or catalog still over the base surface; nothing for
/// the basic backdrops (the studio paints those).
class StudioBackdropFill extends StatelessWidget {
  const StudioBackdropFill({
    required this.backdrop,
    this.visualBuilder,
    super.key,
  });

  final StudioBackdrop backdrop;
  final Widget? Function(String visualId)? visualBuilder;

  @override
  Widget build(BuildContext context) {
    if (backdrop.visualId case final String id) {
      return visualBuilder?.call(id) ?? const SizedBox.shrink();
    }
    return switch (backdrop.colors) {
      [] => const SizedBox.shrink(),
      [final color] => ColoredBox(color: color),
      final colors => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
        ),
      ),
    };
  }
}

/// Lets the user pick what goes behind the visual. Each tap applies at once
/// and the sheet stays open, with no dimming, so backdrops can be compared.
Future<void> showStudioBackdropPicker({
  required BuildContext context,
  required StudioBackdrop current,
  required List<StudioBackdropVisual> visuals,
  required ValueChanged<StudioBackdrop> onSelected,
}) {
  var selected = current;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    barrierColor: Colors.transparent,
    backgroundColor: const Color(0xF20F1715),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder:
        (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) {
            Widget swatch(StudioBackdrop backdrop, Widget preview) =>
                _BackdropSwatch(
                  backdrop: backdrop,
                  preview: preview,
                  selected: backdrop == selected,
                  onTap: () {
                    setSheetState(() => selected = backdrop);
                    onSelected(backdrop);
                  },
                );
            final dark = Theme.of(context).colorScheme.surfaceContainerLowest;
            return DraggableScrollableSheet(
              key: const ValueKey('backdrop-picker'),
              initialChildSize: 0.42,
              minChildSize: 0.25,
              maxChildSize: 0.85,
              expand: false,
              builder:
                  (context, controller) => ListView(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Fondo detrás del visual',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Se ve a través de los overlays transparentes.',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.white60,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cerrar',
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white70,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      _section('Básicos', [
                        swatch(
                          StudioBackdrop.alpha,
                          const CustomPaint(
                            painter: CheckerboardPainter(squareSize: 8),
                          ),
                        ),
                        swatch(StudioBackdrop.dark, ColoredBox(color: dark)),
                        swatch(
                          StudioBackdrop.light,
                          const ColoredBox(color: _lightSurface),
                        ),
                      ]),
                      _section('Colores', [
                        for (final backdrop in studioColorBackdrops)
                          swatch(
                            backdrop,
                            StudioBackdropFill(backdrop: backdrop),
                          ),
                      ]),
                      _section('Degradados', [
                        for (final backdrop in studioGradientBackdrops)
                          swatch(
                            backdrop,
                            StudioBackdropFill(backdrop: backdrop),
                          ),
                      ]),
                      if (visuals.isNotEmpty)
                        _section('Fondos del catálogo (${visuals.length})', [
                          for (final visual in visuals)
                            swatch(
                              StudioBackdrop.visual(visual),
                              visual.thumbnail,
                            ),
                        ]),
                    ],
                  ),
            );
          },
        ),
  );
}

Widget _section(String title, List<Widget> swatches) => Padding(
  padding: const EdgeInsets.only(top: 14),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: Colors.white54,
        ),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 10, children: swatches),
    ],
  ),
);

class _BackdropSwatch extends StatelessWidget {
  const _BackdropSwatch({
    required this.backdrop,
    required this.preview,
    required this.selected,
    required this.onTap,
  });

  final StudioBackdrop backdrop;
  final Widget preview;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      child: Column(
        children: [
          InkWell(
            key: ValueKey('backdrop-${backdrop.id}'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 60,
              height: 60,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? _accent : Colors.white24,
                  width: selected ? 2.5 : 1,
                ),
              ),
              child: SizedBox.expand(child: preview),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            backdrop.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? _accent : Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}

/// The alpha grid: shows what an overlay leaves transparent.
class CheckerboardPainter extends CustomPainter {
  const CheckerboardPainter({
    this.squareSize = 20.0,
    this.lightColor = const Color(0xFF383842),
    this.darkColor = const Color(0xFF1C1C22),
  });

  final double squareSize;
  final Color lightColor;
  final Color darkColor;

  @override
  void paint(Canvas canvas, Size size) {
    final darkPaint = Paint()..color = darkColor;
    final lightPaint = Paint()..color = lightColor;
    canvas.drawRect(Offset.zero & size, darkPaint);

    final xCount = (size.width / squareSize).ceil();
    final yCount = (size.height / squareSize).ceil();

    for (var y = 0; y < yCount; y++) {
      final isEvenRow = y % 2 == 0;
      for (var x = isEvenRow ? 0 : 1; x < xCount; x += 2) {
        canvas.drawRect(
          Rect.fromLTWH(x * squareSize, y * squareSize, squareSize, squareSize),
          lightPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CheckerboardPainter oldDelegate) =>
      oldDelegate.squareSize != squareSize ||
      oldDelegate.lightColor != lightColor ||
      oldDelegate.darkColor != darkColor;
}
