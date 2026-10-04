import 'dart:convert';

import 'package:scene_compositor/scene_compositor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'adjustment_session.dart';
import 'palettes.dart';

/// A look someone saved from Ajustes ("Mía 1"), kept on this device, with
/// its palette when it recolored the visual.
typedef PersonalVariation =
    ({String name, AdjustmentValues values, List<int>? palette});

/// At most this many saved looks per visual.
const personalVariationLimit = 4;

/// Saved looks by modifier id, so they survive edits to the C++: ids that no
/// longer exist are dropped and values outside a new range are left out.
class PersonalVariations {
  PersonalVariations({Future<SharedPreferences> Function()? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _preferences;

  static String _key(String visualId) => 'creator.variations.$visualId';

  Future<List<PersonalVariation>> load(CreatorVisualDefinition visual) async {
    final raw = (await _preferences()).getString(_key(visual.id));
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded.take(personalVariationLimit))
          if (_decode(visual, item) case final PersonalVariation variation)
            variation,
      ];
    } on FormatException {
      return const [];
    }
  }

  Future<void> save(
    CreatorVisualDefinition visual,
    List<PersonalVariation> variations,
  ) async {
    final preferences = await _preferences();
    if (variations.isEmpty) {
      await preferences.remove(_key(visual.id));
      return;
    }
    await preferences.setString(
      _key(visual.id),
      jsonEncode([
        for (final variation in variations.take(personalVariationLimit))
          {
            'name': variation.name,
            'values': {
              ...variation.values.controls.toMap(),
              ...variation.values.modifiers,
            },
            if (variation.palette case final List<int> palette)
              'palette': palette,
          },
      ]),
    );
  }

  /// Why [name] cannot name a saved look of [visual], or null when it can:
  /// up to 20 characters (as variations count them), and never the name of
  /// Original, of an author variation or of another saved look.
  static String? nameProblem(
    String name,
    CreatorVisualDefinition visual,
    List<PersonalVariation> saved, {
    String? except,
  }) {
    final key = name.trim().toLowerCase();
    if (key.isEmpty || name.trim().length > 20) {
      return 'Usa un nombre de 1 a 20 caracteres.';
    }
    final taken = {
      originalChipName.toLowerCase(),
      for (final variation in visual.variations) variation.name.toLowerCase(),
      for (final variation in saved)
        if (variation.name != except) variation.name.toLowerCase(),
    };
    return taken.contains(key) ? 'Ese nombre ya existe; elige otro.' : null;
  }

  /// Next free "Mía N" name.
  static String nextName(List<PersonalVariation> saved) {
    var index = 1;
    while (saved.any((variation) => variation.name == 'Mía $index')) {
      index++;
    }
    return 'Mía $index';
  }

  static PersonalVariation? _decode(
    CreatorVisualDefinition visual,
    Object? item,
  ) {
    if (item is! Map || item['name'] is! String || item['values'] is! Map) {
      return null;
    }
    final values = item['values'] as Map;
    final basics = visual.controls.toMap();
    for (final (id, _, lowest) in adjustmentBasics) {
      final value = values[id];
      if (value is num && value.isFinite && value >= lowest && value <= 2) {
        basics[id] = value.toDouble();
      }
    }
    final modifiers = visual.modifierDefaults;
    for (final modifier in visual.modifiers) {
      final value = values[modifier.id];
      if (value is num && modifier.accepts(value.toDouble())) {
        modifiers[modifier.id] = value.toDouble();
      }
    }
    final result = (
      controls: CreatorControls(
        intensity: basics['intensity']!,
        speed: basics['speed']!,
        detail: basics['detail']!,
        glow: basics['glow']!,
      ),
      modifiers: Map<String, double>.unmodifiable(modifiers),
    );
    final original = (
      controls: visual.controls,
      modifiers: visual.modifierDefaults,
    );
    final raw = item['palette'];
    final palette =
        raw is List &&
                raw.length == 4 &&
                raw.every((c) => c is int && c >= 0 && c <= 0xffffffff) &&
                usesPalette(visual)
            ? paletteFor(visual, raw.cast<int>())
            : null;
    // A look that no longer changes anything is gone.
    if (sameAdjustmentValues(result, original) && palette == null) return null;
    final name = (item['name'] as String).trim();
    return (
      name: name.isEmpty || name.length > 20 ? 'Mía' : name,
      values: result,
      palette: palette,
    );
  }
}
