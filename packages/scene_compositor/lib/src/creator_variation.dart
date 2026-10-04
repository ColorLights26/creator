import 'creator_visual_definition.dart';

/// At most this many author variations per visual.
const creatorMaximumVariations = 4;

/// The basic settings a variation may change, besides the modifiers.
const creatorVariationBasics = {'intensity', 'speed', 'detail', 'glow'};

/// A named look of one visual, declared by its author next to the modifiers:
/// `CreatorVariation('Tormenta', {'brazos': 7, 'pulso': 'Golpes'})`.
///
/// Keys are modifier ids or the basics (intensity, speed, detail, glow).
/// A slider, steps or basic takes a number, a toggle true/false and a choice
/// the text of its option, so reordering options never changes a variation.
/// Keys left out keep their initial value. Studio shows variations as chips;
/// they never reach the engine catalog, only the metadata.
class CreatorVariation {
  const CreatorVariation(this.name, this.values);

  final String name;
  final Map<String, Object> values;

  Map<String, Object> toMap() => {'name': name, 'values': values};

  /// The settings of [visual] with this variation applied over the initial
  /// ones. Throws [FormatException] for a key or value [visual] does not have.
  ({CreatorControls controls, Map<String, double> modifiers}) resolve(
    CreatorVisualDefinition visual,
  ) {
    final basics = visual.controls.toMap();
    final modifiers = visual.modifierDefaults;
    for (final MapEntry(:key, :value) in values.entries) {
      if (creatorVariationBasics.contains(key)) {
        if (value is! num || !value.isFinite) {
          throw FormatException('$name: $key necesita un número.');
        }
        basics[key] = value.toDouble();
        continue;
      }
      final modifier = visual.modifiers.where((m) => m.id == key).firstOrNull;
      if (modifier == null) {
        throw FormatException(
          '$name: «$key» no es un modificador ni un ajuste básico.',
        );
      }
      final number = switch (modifier.kind) {
        CreatorModifierKind.toggle when value is bool => value ? 1.0 : 0.0,
        CreatorModifierKind.choice when value is String =>
          modifier.options.indexOf(value).toDouble(),
        CreatorModifierKind.slider ||
        CreatorModifierKind.steps when value is num => value.toDouble(),
        _ => null,
      };
      if (number == null || !modifier.accepts(number)) {
        throw FormatException(switch (modifier.kind) {
          CreatorModifierKind.toggle => '$name: $key va con true o false.',
          CreatorModifierKind.choice =>
            '$name: $key debe ser una de sus opciones: '
                '${modifier.options.join(', ')}.',
          _ =>
            '$name: $key debe estar entre ${modifier.lower} y '
                '${modifier.upper}${modifier.kind == CreatorModifierKind.steps ? ', entero' : ''}.',
        });
      }
      modifiers[key] = number;
    }
    final controls = CreatorControls(
      intensity: basics['intensity']!,
      speed: basics['speed']!,
      detail: basics['detail']!,
      glow: basics['glow']!,
    );
    try {
      controls.validate();
    } on ArgumentError {
      throw FormatException(
        '$name: intensity, speed y glow van de 0 a 2; detail de 0.25 a 2.',
      );
    }
    return (controls: controls, modifiers: modifiers);
  }
}

/// Data rules for a visual's variations; part of [validateCreatorCatalog].
void validateCreatorVariations(
  CreatorVisualDefinition visual,
  void Function(bool condition, String message) require,
) {
  final variations = visual.variations;
  if (variations.isEmpty) return;
  require(
    visual.isNative,
    'Las variaciones sólo existen en visuales con nativeSource.',
  );
  require(
    variations.length <= creatorMaximumVariations,
    'Máximo $creatorMaximumVariations variaciones.',
  );
  final names = <String>{};
  final initial = (
    controls: visual.controls.toMap(),
    modifiers: visual.modifierDefaults,
  );
  for (final variation in variations) {
    final name = variation.name.trim();
    require(
      name.isNotEmpty && name.length <= 20,
      'Variación «${variation.name}»: el nombre debe tener de 1 a 20 caracteres.',
    );
    require(
      name.toLowerCase() != 'original',
      'Variación «$name»: «Original» ya existe, elige otro nombre.',
    );
    require(
      names.add(name.toLowerCase()),
      'Variación «$name» repetida.',
    );
    require(
      variation.values.isNotEmpty,
      'Variación «$name»: indica al menos un ajuste.',
    );
    final ({CreatorControls controls, Map<String, double> modifiers}) resolved;
    try {
      resolved = variation.resolve(visual);
    } on FormatException catch (error) {
      require(false, 'Variación ${error.message}');
      return;
    }
    final controls = resolved.controls.toMap();
    require(
      controls.keys.any((k) => controls[k] != initial.controls[k]) ||
          resolved.modifiers.keys.any(
            (k) => resolved.modifiers[k] != initial.modifiers[k],
          ),
      'Variación «$name»: es igual al original; cambia algún ajuste.',
    );
  }
}
