/// The controls and modifiers one probe plays. Pure Dart.
library;

import 'package:scene_compositor/authoring.dart';

import 'energy_probe_spec.dart';

/// The loud basics of the native sweep (`authored_probe.cpp`, `sweep()`):
/// intensity, speed, detail, glow.
const energyProbeLoudControls = CreatorControls(
  intensity: 2,
  speed: 1,
  detail: 2,
  glow: 2,
);

/// Settings sent to the compositor for one probe run.
class EnergyProbeProfile {
  const EnergyProbeProfile({
    required this.kind,
    required this.controls,
    required this.modifiers,
    this.variation,
  });

  final EnergyProbeProfileKind kind;

  /// Name of the author's variation, only for [EnergyProbeProfileKind.variation].
  final String? variation;
  final CreatorControls controls;

  /// Every modifier of the visual, by id.
  final Map<String, double> modifiers;

  /// `creator.profile` of the record.
  Map<String, Object?> toMap() => {
    'name': kind.label,
    'variation': variation,
    'controls': controls.toMap(),
    'modifiers': modifiers,
  };
}

/// Resolves [spec] against [visual]: the initial values, every setting at its
/// maximum or one declared variation. Throws [FormatException] for a
/// variation index the visual does not have.
EnergyProbeProfile resolveEnergyProbeProfile(
  CreatorVisualDefinition visual,
  EnergyProbeSpec spec,
) {
  switch (spec.profile) {
    case EnergyProbeProfileKind.initial:
      return EnergyProbeProfile(
        kind: spec.profile,
        controls: visual.controls,
        modifiers: visual.modifierDefaults,
      );
    case EnergyProbeProfileKind.max:
      return EnergyProbeProfile(
        kind: spec.profile,
        controls: energyProbeLoudControls,
        modifiers: {
          for (final modifier in visual.modifiers) modifier.id: modifier.upper,
        },
      );
    case EnergyProbeProfileKind.variation:
      final index = spec.variationIndex!;
      if (index >= visual.variations.length) {
        throw FormatException(
          '${visual.id} tiene ${visual.variations.length} variaciones; no '
          'existe la ${index + 1}ª (índice $index).',
        );
      }
      final variation = visual.variations[index];
      final resolved = variation.resolve(visual);
      return EnergyProbeProfile(
        kind: spec.profile,
        variation: variation.name,
        controls: resolved.controls,
        modifiers: resolved.modifiers,
      );
  }
}
