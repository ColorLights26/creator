import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scene_compositor/scene_compositor.dart';

const _accent = Color(0xFF73F572);

/// The four settings every visual has, with the names shown in Ajustes.
const _basics = [
  ('intensity', 'Intensidad', 0.0),
  ('speed', 'Velocidad', 0.0),
  ('detail', 'Detalle', .25),
  ('glow', 'Brillo', 0.0),
];

/// Opens Ajustes for [visual]. Every change applies live through the
/// callbacks; the sheet does not dim the visual so the effect stays visible.
Future<void> showVisualAdjustments({
  required BuildContext context,
  required CreatorVisualDefinition visual,
  required CreatorControls controls,
  required Map<String, double> modifiers,
  required ValueChanged<CreatorControls> onControls,
  required ValueChanged<Map<String, double>> onModifiers,
}) {
  var currentControls = controls.toMap();
  var currentModifiers = {...visual.modifierDefaults, ...modifiers};
  final random = math.Random();
  final source = [
    visual.nativeSource,
    visual.shaderSource,
    ...visual.shaderSources.values,
  ].join('\n');
  bool reads(String name) => RegExp('\\.$name\\b').hasMatch(source);

  CreatorControls asControls(Map<String, double> values) => CreatorControls(
    intensity: values['intensity']!,
    speed: values['speed']!,
    detail: values['detail']!,
    glow: values['glow']!,
  );

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
            void setControl(String id, double value) {
              setSheetState(() {
                currentControls = {...currentControls, id: value};
              });
              onControls(asControls(currentControls));
            }

            void setModifier(String id, double value) {
              setSheetState(() {
                currentModifiers = {...currentModifiers, id: value};
              });
              onModifiers(Map.unmodifiable(currentModifiers));
            }

            void reset() {
              setSheetState(() {
                currentControls = visual.controls.toMap();
                currentModifiers = visual.modifierDefaults;
              });
              onControls(visual.controls);
              onModifiers(visual.modifierDefaults);
            }

            // Basics stay in a band that still looks right; modifiers use
            // the whole range their author declared.
            void shuffle() {
              double between(double low, double high) =>
                  low + random.nextDouble() * (high - low);
              setSheetState(() {
                currentControls = {
                  for (final (id, _, _) in _basics)
                    id: reads(id) ? between(.5, 1.5) : currentControls[id]!,
                };
                currentModifiers = {
                  for (final modifier in visual.modifiers)
                    modifier.id: switch (modifier.kind) {
                      CreatorModifierKind.slider => between(
                        modifier.lower,
                        modifier.upper,
                      ),
                      _ =>
                        (modifier.lower +
                                random.nextInt(
                                  (modifier.upper - modifier.lower).toInt() + 1,
                                ))
                            .toDouble(),
                    },
                };
              });
              onControls(asControls(currentControls));
              onModifiers(Map.unmodifiable(currentModifiers));
            }

            Future<void> copy() async {
              final text = _snippet(visual, currentControls, currentModifiers);
              debugPrint(text);
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Valores copiados. Pégalos en la metadata y en '
                      'modifiers para que sean los iniciales.',
                    ),
                  ),
                );
              }
            }

            return DraggableScrollableSheet(
              key: const ValueKey('visual-adjustments'),
              initialChildSize: .5,
              minChildSize: .25,
              maxChildSize: .9,
              expand: false,
              builder:
                  (context, controller) => ListView(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
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
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Ajustes · ${visual.name}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'Se aplican en vivo. El voto es para los '
                                  'valores originales.',
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
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _action(
                            'adjustments-reset',
                            Icons.restart_alt_rounded,
                            'Restablecer',
                            reset,
                          ),
                          _action(
                            'adjustments-shuffle',
                            Icons.casino_rounded,
                            'Aleatorio',
                            shuffle,
                          ),
                          _action(
                            'adjustments-copy',
                            Icons.content_copy_rounded,
                            'Copiar valores',
                            () => unawaited(copy()),
                          ),
                        ],
                      ),
                      _heading(
                        visual.modifiers.isEmpty
                            ? 'MODIFICADORES'
                            : 'MODIFICADORES DE ESTE VISUAL',
                      ),
                      if (visual.modifiers.isEmpty)
                        const Text(
                          'Este visual no tiene modificadores propios. Los '
                          'visuales nuevos los traen: la plantilla le pide a '
                          'la IA que los cree.',
                          key: ValueKey('adjustments-no-modifiers'),
                          style: TextStyle(color: Colors.white60, height: 1.3),
                        )
                      else
                        for (final modifier in visual.modifiers)
                          _ModifierControl(
                            modifier: modifier,
                            value: currentModifiers[modifier.id]!,
                            onChanged:
                                (value) => setModifier(modifier.id, value),
                          ),
                      _heading('BÁSICOS'),
                      for (final (id, label, lowest) in _basics)
                        _Labeled(
                          key: ValueKey('adjustments-basic-$id'),
                          label: label,
                          value: currentControls[id]!.toStringAsFixed(2),
                          note: reads(id) ? null : 'este visual no lo usa',
                          child: Slider(
                            value: currentControls[id]!,
                            min: lowest,
                            max: 2,
                            activeColor: _accent,
                            onChanged:
                                reads(id)
                                    ? (value) => setControl(id, value)
                                    : null,
                          ),
                        ),
                    ],
                  ),
            );
          },
        ),
  );
}

/// The chosen values as Dart, to paste where the initial values live.
String _snippet(
  CreatorVisualDefinition visual,
  Map<String, double> controls,
  Map<String, double> modifiers,
) {
  String number(double value) {
    final rounded = (value * 100).round() / 100;
    return rounded == rounded.roundToDouble()
        ? rounded.toInt().toString()
        : rounded.toString();
  }

  final lines = <String>[
    '// Ajustes elegidos para ${visual.id}.',
    '// En ${visual.id}_metadata.dart:',
    'controls: CreatorControls(${[for (final (id, _, _) in _basics) '$id: ${number(controls[id]!)}'].join(', ')}),',
  ];
  if (visual.modifiers.isNotEmpty) {
    lines.add('// En ${visual.id}.dart, el value: de cada modificador:');
    for (final modifier in visual.modifiers) {
      final value = modifiers[modifier.id]!;
      lines.add(
        '// ${modifier.id}: ${switch (modifier.kind) {
          CreatorModifierKind.toggle => value == 1 ? 'true' : 'false',
          CreatorModifierKind.choice => '${value.toInt()} (${modifier.options[value.toInt()]})',
          CreatorModifierKind.slider => _sliderText(modifier, value),
          CreatorModifierKind.steps => value.toInt().toString(),
        }}',
      );
    }
  }
  return lines.join('\n');
}

/// A slider value with enough decimals for its range (a thousandth of it),
/// never outside the range, so pasting it back as `value:` stays valid.
String _sliderText(CreatorModifier modifier, double value) {
  final span = modifier.upper - modifier.lower;
  final decimals = (-math.log(span / 1000) / math.ln10).ceil().clamp(2, 6);
  final rounded = double.parse(
    value.toStringAsFixed(decimals),
  ).clamp(modifier.lower, modifier.upper);
  return rounded == rounded.roundToDouble()
      ? rounded.toInt().toString()
      : rounded.toString();
}

Widget _heading(String text) => Padding(
  padding: const EdgeInsets.only(top: 18, bottom: 6),
  child: Text(
    text,
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.8,
      color: Colors.white54,
    ),
  ),
);

Widget _action(String key, IconData icon, String label, VoidCallback onTap) =>
    OutlinedButton.icon(
      key: ValueKey(key),
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white24),
        visualDensity: VisualDensity.compact,
      ),
      icon: Icon(icon, size: 16, color: _accent),
      label: Text(label),
    );

class _ModifierControl extends StatelessWidget {
  const _ModifierControl({
    required this.modifier,
    required this.value,
    required this.onChanged,
  });

  final CreatorModifier modifier;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final key = ValueKey('adjustments-modifier-${modifier.id}');
    switch (modifier.kind) {
      case CreatorModifierKind.toggle:
        return _Labeled(
          key: key,
          label: modifier.label,
          value: value == 1 ? 'Sí' : 'No',
          child: Align(
            alignment: Alignment.centerLeft,
            child: Switch(
              value: value == 1,
              activeThumbColor: _accent,
              onChanged: (on) => onChanged(on ? 1 : 0),
            ),
          ),
        );
      case CreatorModifierKind.choice:
        return _Labeled(
          key: key,
          label: modifier.label,
          value: modifier.options[value.toInt()],
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (var index = 0; index < modifier.options.length; index++)
                ChoiceChip(
                  key: ValueKey('adjustments-modifier-${modifier.id}-$index'),
                  label: Text(modifier.options[index]),
                  selected: value.toInt() == index,
                  selectedColor: _accent.withValues(alpha: .25),
                  onSelected: (_) => onChanged(index.toDouble()),
                ),
            ],
          ),
        );
      case CreatorModifierKind.slider:
      case CreatorModifierKind.steps:
        final steps = modifier.kind == CreatorModifierKind.steps;
        return _Labeled(
          key: key,
          label: modifier.label,
          value:
              steps ? value.toInt().toString() : _sliderText(modifier, value),
          child: Slider(
            value: value,
            min: modifier.lower,
            max: modifier.upper,
            divisions: steps ? (modifier.upper - modifier.lower).toInt() : null,
            activeColor: _accent,
            onChanged: (next) => onChanged(steps ? next.roundToDouble() : next),
          ),
        );
    }
  }
}

class _Labeled extends StatelessWidget {
  const _Labeled({
    required this.label,
    required this.value,
    required this.child,
    this.note,
    super.key,
  });

  final String label;
  final String value;
  final String? note;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  note == null ? label : '$label · $note',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: note == null ? Colors.white : Colors.white38,
                  ),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: note == null ? _accent : Colors.white38,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          child,
        ],
      ),
    );
  }
}

/// The button above "Pruébalo con": opens Ajustes and says how many
/// modifiers of its own the visual has.
class VisualAdjustmentsButton extends StatelessWidget {
  const VisualAdjustmentsButton({
    required this.modifierCount,
    required this.modified,
    required this.onPressed,
    super.key,
  });

  final int modifierCount;

  /// Something differs from the visual's initial values.
  final bool modified;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: OutlinedButton.icon(
        key: const ValueKey('visual-adjustments-button'),
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: modified ? _accent : Colors.white24),
          visualDensity: VisualDensity.compact,
        ),
        icon: Icon(
          Icons.tune_rounded,
          size: 16,
          color: modifierCount > 0 || modified ? _accent : Colors.white70,
        ),
        label: Text(
          [
            'Ajustes',
            if (modifierCount > 0)
              '$modifierCount ${modifierCount == 1 ? 'modificador' : 'modificadores'}',
            if (modified) 'cambiados',
          ].join(' · '),
        ),
      ),
    );
  }
}
