import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:scene_compositor/scene_compositor.dart';

import 'palettes.dart';

/// The settings of one visual: its four basics and its modifiers by id.
typedef AdjustmentValues =
    ({CreatorControls controls, Map<String, double> modifiers});

/// The name shown for the visual's initial values.
const originalChipName = 'Original';

/// The basics every visual has, as Ajustes names them.
const adjustmentBasics = [
  ('intensity', 'Intensidad', 0.0),
  ('speed', 'Velocidad', 0.0),
  ('detail', 'Detalle', .25),
  ('glow', 'Brillo', 0.0),
];

/// What the team explores for one visual during a Studio session: the values
/// on screen, an undo history, the seed and the "show the original" compare.
/// Pure state; Studio sends [shown] to the compositor whenever it changes.
class AdjustmentSession extends ChangeNotifier {
  AdjustmentSession(this.visual, {math.Random? random})
    : _random = random ?? math.Random(),
      original = (
        controls: visual.controls,
        modifiers: Map.unmodifiable(visual.modifierDefaults),
      ),
      usedBasics = _usedBasics(visual),
      recolorable = usesPalette(visual) {
    _current = original;
  }

  final CreatorVisualDefinition visual;
  final AdjustmentValues original;

  /// Basics the visual's code reads; the others are hidden in Ajustes.
  final Set<String> usedBasics;

  /// The visual reads its colors, so a live palette can recolor it.
  final bool recolorable;
  final math.Random _random;
  late AdjustmentValues _current;
  final List<({AdjustmentValues values, String? chip, List<int>? palette})>
  _history = [];
  String? _chip = originalChipName;
  List<int>? _palette;
  int? _seed;
  bool _comparing = false;
  bool _jumped = false;

  static const historyLimit = 20;

  /// The values the team chose (what returns after a compare).
  AdjustmentValues get current => _current;

  /// What the compositor should show right now.
  AdjustmentValues get shown => _comparing ? original : _current;

  /// Colors in place of the visual's own, or null for its own.
  List<int>? get palette => _palette;
  List<int>? get shownPalette => _comparing ? null : _palette;

  /// The chip whose values are on screen, or null after a manual change.
  String? get chip => _chip;

  /// A seed other than the recording's, or null for the recording's.
  int? get seed => _seed;
  bool get comparing => _comparing;
  bool get canUndo => _history.isNotEmpty;

  /// The last change replaced values at once (chip, dice, undo, compare)
  /// instead of following a finger, so Studio can animate the basics.
  bool get jumped => _jumped;

  bool get differsFromOriginal =>
      _seed != null ||
      _palette != null ||
      !sameAdjustmentValues(_current, original);

  /// A finger moved a control: no history entry per frame ([beginEdit] adds
  /// one when the gesture starts).
  void set(String id, double value) {
    final next = _with(_current, id, value);
    if (sameAdjustmentValues(next, _current)) return;
    _current = next;
    _chip = null;
    _changed(jumped: false);
  }

  /// Saves the values before a gesture so [undo] returns to them.
  void beginEdit() => _remember();

  /// Shows a chip's values (Original, an author or a personal variation).
  /// A saved look brings its [palette]; an author's keeps the current one.
  void apply(String name, AdjustmentValues values, {List<int>? palette}) {
    _remember();
    _current = values;
    _chip = name;
    if (palette != null) _palette = palette;
    _changed(jumped: true);
  }

  /// Recolors the visual (null: its own colors).
  void setPalette(List<int>? colors) {
    if (listEquals(colors, _palette)) return;
    _remember();
    _palette = colors == null ? null : List.unmodifiable(colors);
    _changed(jumped: true);
  }

  /// Back to the initial values, colors and the recording's seed.
  void resetToOriginal() {
    _remember();
    _current = original;
    _chip = originalChipName;
    _seed = null;
    _palette = null;
    _changed(jumped: true);
  }

  /// A small change around the current values; always changes something.
  void vary() {
    _remember();
    final modifiers = {..._current.modifiers};
    final basics = _current.controls.toMap();
    for (var attempt = 0; attempt < 8; attempt++) {
      for (final modifier in visual.modifiers) {
        final now = modifiers[modifier.id]!;
        modifiers[modifier.id] = switch (modifier.kind) {
          CreatorModifierKind.slider => (now +
                  (_random.nextDouble() - _random.nextDouble()) *
                      .2 *
                      (modifier.upper - modifier.lower))
              .clamp(modifier.lower, modifier.upper),
          CreatorModifierKind.steps => (now + (_random.nextInt(5) - 2)).clamp(
            modifier.lower,
            modifier.upper,
          ),
          CreatorModifierKind.choice =>
            _random.nextDouble() < .35 ? _otherOption(modifier, now) : now,
          CreatorModifierKind.toggle =>
            _random.nextDouble() < .2 ? 1 - now : now,
        };
      }
      for (final id in usedBasics) {
        basics[id] = (basics[id]! + (_random.nextDouble() - .5) * .4).clamp(
          .5,
          1.5,
        );
      }
      final changed =
          visual.modifiers.isEmpty
              ? !mapEquals(basics, _current.controls.toMap())
              : !mapEquals(modifiers, _current.modifiers);
      if (changed) break;
    }
    _current = (
      controls: _controls(basics),
      modifiers: Map.unmodifiable(modifiers),
    );
    _chip = null;
    _changed(jumped: true);
  }

  /// Anywhere in the declared ranges, sometimes in other colors.
  void surprise() {
    _remember();
    if (recolorable) {
      final pick = _random.nextInt(studioPalettes.length + 2);
      _palette =
          pick < studioPalettes.length
              ? paletteFor(visual, studioPalettes[pick].colors)
              : pick == studioPalettes.length
              ? harmonicPalette(visual, _random)
              : null;
    }
    final basics = _current.controls.toMap();
    for (final id in usedBasics) {
      basics[id] = .6 + _random.nextDouble() * .8;
    }
    _current = (
      controls: _controls(basics),
      modifiers: Map.unmodifiable({
        for (final modifier in visual.modifiers)
          modifier.id: switch (modifier.kind) {
            CreatorModifierKind.slider =>
              modifier.lower +
                  _random.nextDouble() * (modifier.upper - modifier.lower),
            _ =>
              modifier.lower +
                  _random.nextInt(
                    (modifier.upper - modifier.lower).toInt() + 1,
                  ),
          },
      }),
    );
    _chip = null;
    _changed(jumped: true);
  }

  void undo() {
    if (_history.isEmpty) return;
    final previous = _history.removeLast();
    _current = previous.values;
    _chip = previous.chip;
    _palette = previous.palette;
    _changed(jumped: true);
  }

  /// Hold to compare: [shown] becomes the original until released.
  set comparing(bool value) {
    if (value == _comparing) return;
    _comparing = value;
    _changed(jumped: true);
  }

  /// Another arrangement of the same visual, or null for the recording's.
  set seed(int? value) {
    if (value == _seed) return;
    _seed = value;
    _changed(jumped: false);
  }

  void _remember() {
    _history.add((values: _current, chip: _chip, palette: _palette));
    if (_history.length > historyLimit) _history.removeAt(0);
  }

  void _changed({required bool jumped}) {
    _jumped = jumped;
    notifyListeners();
  }

  double _otherOption(CreatorModifier modifier, double now) {
    final count = modifier.options.length;
    final shift = 1 + _random.nextInt(count - 1);
    return ((now.toInt() + shift) % count).toDouble();
  }

  AdjustmentValues _with(AdjustmentValues values, String id, double value) {
    if (values.modifiers.containsKey(id)) {
      return (
        controls: values.controls,
        modifiers: Map.unmodifiable({...values.modifiers, id: value}),
      );
    }
    return (
      controls: _controls({...values.controls.toMap(), id: value}),
      modifiers: values.modifiers,
    );
  }

  static CreatorControls _controls(Map<String, double> basics) =>
      CreatorControls(
        intensity: basics['intensity']!,
        speed: basics['speed']!,
        detail: basics['detail']!,
        glow: basics['glow']!,
      );

  static Set<String> _usedBasics(CreatorVisualDefinition visual) {
    final source = [
      visual.nativeSource,
      visual.shaderSource,
      ...visual.shaderSources.values,
    ].join('\n');
    return {
      for (final (id, _, _) in adjustmentBasics)
        if (RegExp('\\.$id\\b').hasMatch(source)) id,
    };
  }
}

bool sameAdjustmentValues(AdjustmentValues a, AdjustmentValues b) =>
    mapEquals(a.controls.toMap(), b.controls.toMap()) &&
    mapEquals(a.modifiers, b.modifiers);

/// [values] as an author variation the team can hand back to the AI: only
/// what differs from [visual]'s initial values, choices by their text. A
/// [palette] goes to the metadata, where the visual's colors live.
String variationForAi(
  CreatorVisualDefinition visual,
  String name,
  AdjustmentValues values, {
  List<int>? palette,
}) {
  final entries = <String>[];
  for (final modifier in visual.modifiers) {
    final value = values.modifiers[modifier.id]!;
    if (value == modifier.value.toDouble()) continue;
    entries.add(
      "'${modifier.id}': ${switch (modifier.kind) {
        CreatorModifierKind.toggle => value == 1 ? 'true' : 'false',
        CreatorModifierKind.choice => "'${modifier.options[value.toInt()]}'",
        CreatorModifierKind.steps => value.toInt().toString(),
        CreatorModifierKind.slider => sliderText(modifier.lower, modifier.upper, value),
      }}",
    );
  }
  final initial = visual.controls.toMap();
  for (final MapEntry(:key, :value) in values.controls.toMap().entries) {
    if (value != initial[key]) {
      entries.add("'$key': ${sliderText(0, 2, value)}");
    }
  }
  final safeName = name.replaceAll(RegExp(r"[\\'$]"), '');
  final colors =
      palette == null
          ? ''
          : '\nY en el archivo _metadata, para que esta paleta sea la original, '
              'usa colors: [${palette.map((c) => '0x${c.toRadixString(16).padLeft(8, '0')}').join(', ')}],';
  if (entries.isEmpty) {
    return colors.isEmpty
        ? 'Este visual se ve como el original: no hay nada que copiar.'
        : colors.trim();
  }
  return 'En este visual agrega esta variación dentro de const variations '
      '(créala justo después de const modifiers si no existe). '
      'No cambies nada más:\n'
      "CreatorVariation('$safeName', {${entries.join(', ')}}),$colors";
}

/// A value with enough decimals for its range (a thousandth of it), never
/// outside the range, so pasting it back stays valid.
String sliderText(double lower, double upper, double value) {
  final decimals = (-math.log((upper - lower) / 1000) / math.ln10).ceil().clamp(
    2,
    6,
  );
  final rounded = double.parse(
    value.toStringAsFixed(decimals),
  ).clamp(lower, upper);
  return rounded == rounded.roundToDouble()
      ? rounded.toInt().toString()
      : rounded.toString();
}
