/// What `--colorlights-qa-scene energy-probe=<spec>` asks the studio to
/// measure. Pure Dart: no Flutter, no catalog.
library;

/// Launch option the host driver passes (the same one the main app reads).
const energyProbeLaunchOption = '--colorlights-qa-scene';

/// Value prefix that selects the energy probe instead of the normal studio.
const energyProbeLabelPrefix = 'energy-probe=';

/// The probe screen alone, with no visual: the reference every visual is
/// compared to.
const energyProbeBaselineId = 'baseline';

/// Catalog visual IDs (see `validateCreatorCatalog`).
final RegExp _visualIdPattern = RegExp(r'^[a-z][a-z0-9_]{0,63}$');

/// Which settings of the visual the probe plays.
enum EnergyProbeProfileKind {
  /// The author's initial controls and modifier values.
  initial('default'),

  /// Loud basics and every modifier at its upper value.
  max('max'),

  /// One of the author's named variations.
  variation('variation');

  const EnergyProbeProfileKind(this.label);

  /// Name written in the record (`creator.profile.name`).
  final String label;
}

/// A parsed probe label: `baseline`, `<visualId>`, `<visualId>@max` or
/// `<visualId>@variation=<index>`.
class EnergyProbeSpec {
  const EnergyProbeSpec._({
    required this.text,
    required this.visualId,
    required this.profile,
    this.variationIndex,
  });

  /// The exact text after `energy-probe=`; the `visual` key of every record.
  final String text;

  /// Null for the baseline.
  final String? visualId;
  final EnergyProbeProfileKind profile;

  /// Index into `visual.variations` when [profile] is a variation.
  final int? variationIndex;

  bool get baseline => visualId == null;
}

/// Parses the text after `energy-probe=`. Throws [FormatException] with a
/// plain-language message for anything that is not a valid spec.
EnergyProbeSpec parseEnergyProbeSpec(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    throw const FormatException(
      'El spec está vacío. Usa baseline, <visualId>, <visualId>@max o '
      '<visualId>@variation=<índice>.',
    );
  }
  if (text == energyProbeBaselineId) {
    return EnergyProbeSpec._(
      text: text,
      visualId: null,
      profile: EnergyProbeProfileKind.initial,
    );
  }
  final at = text.indexOf('@');
  final visualId = at < 0 ? text : text.substring(0, at);
  if (visualId == energyProbeBaselineId) {
    throw const FormatException(
      'baseline no admite perfil: usa solo baseline.',
    );
  }
  if (!_visualIdPattern.hasMatch(visualId)) {
    throw FormatException(
      '«$visualId» no es un ID de visual válido (letras a-z, números y _, '
      'empieza por letra).',
    );
  }
  if (at < 0) {
    return EnergyProbeSpec._(
      text: text,
      visualId: visualId,
      profile: EnergyProbeProfileKind.initial,
    );
  }
  final suffix = text.substring(at + 1);
  if (suffix == EnergyProbeProfileKind.max.label) {
    return EnergyProbeSpec._(
      text: text,
      visualId: visualId,
      profile: EnergyProbeProfileKind.max,
    );
  }
  const variationPrefix = 'variation=';
  if (suffix.startsWith(variationPrefix)) {
    final index = int.tryParse(suffix.substring(variationPrefix.length));
    if (index == null || index < 0) {
      throw FormatException(
        '«$suffix»: el índice de la variación debe ser un entero desde 0.',
      );
    }
    return EnergyProbeSpec._(
      text: text,
      visualId: visualId,
      profile: EnergyProbeProfileKind.variation,
      variationIndex: index,
    );
  }
  throw FormatException(
    '«@$suffix» no es un perfil. Usa @max o @variation=<índice>.',
  );
}

/// The probe spec text carried by the process arguments, or null when this
/// launch is not an energy probe. Accepts `--colorlights-qa-scene <value>`
/// and `--colorlights-qa-scene=<value>`; a value without the probe prefix is
/// not a probe.
String? energyProbeSpecFromArguments(List<String> arguments) {
  String? value;
  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    if (argument == energyProbeLaunchOption) {
      if (i + 1 < arguments.length) value = arguments[i + 1];
      break;
    }
    if (argument.startsWith('$energyProbeLaunchOption=')) {
      value = argument.substring(energyProbeLaunchOption.length + 1);
      break;
    }
  }
  final trimmed = value?.trim();
  if (trimmed == null || !trimmed.startsWith(energyProbeLabelPrefix)) {
    return null;
  }
  return trimmed.substring(energyProbeLabelPrefix.length);
}
