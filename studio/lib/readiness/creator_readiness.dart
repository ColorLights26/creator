/// Technical readiness of each catalog visual, as the studio shows it.
///
/// Pure Dart. The full registry (`readiness/registry.json`, written by
/// `studio/tool/readiness.dart`) keeps hashes, every check and its
/// evidence; the studio only reads the small export
/// (`readiness/studio_readiness.json`): id, revision, state and a label a
/// collaborator understands. Technical state and the team's 1-10 vote are
/// separate facts: neither one decides the other.
library;

import 'dart:convert';

enum CreatorReadinessState {
  /// Every Mac check passed and the device cost card is within its slot
  /// ceiling for this exact technical identity (sources, resources, engine,
  /// cadence, surface profile).
  verified,

  /// Mac checks passed (or some are not run yet) and the device evidence is
  /// missing: a build, a Mac estimate or a human vote never make it ready.
  pendingEvidence,

  /// A Mac check failed (replay, modifier sweep, pass gate or Metal) or the
  /// harness recorded a frame over the production guard: the drawing needs
  /// work. A Mac time estimate never sets this; when it cannot reach 30 FPS
  /// the visual stays pendingEvidence with a high measurement priority.
  needsRepair,

  /// The registry has no evidence for this revision (new or changed visual,
  /// or the registry was not refreshed).
  unknown;

  static CreatorReadinessState parse(Object? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return unknown;
  }

  /// Short label for the ranking and the summary (no hashes, no jargon).
  String get label => switch (this) {
    verified => 'Comprobado en el dispositivo indicado',
    pendingEvidence => 'Pendiente de evidencia del dispositivo',
    needsRepair => 'Necesita reparación',
    unknown => 'Sin comprobar esta versión',
  };
}

class CreatorReadinessEntry {
  const CreatorReadinessEntry({
    required this.id,
    required this.revision,
    required this.state,
    this.detail = '',
    this.scope = '',
  });

  factory CreatorReadinessEntry.fromJson(
    String id,
    Map<String, Object?> json,
  ) => CreatorReadinessEntry(
    id: id,
    revision: json['revision'] as String? ?? '',
    state: CreatorReadinessState.parse(json['state']),
    detail: json['detail'] as String? ?? '',
    scope: json['scope'] as String? ?? '',
  );

  final String id;

  /// Vote fingerprint the evidence belongs to.
  final String revision;
  final CreatorReadinessState state;

  /// One human sentence: what is missing or what failed.
  final String detail;

  /// What the evidence covers (initial values; extremes warn on iPad...).
  final String scope;

  Map<String, Object> toJson() => {
    'revision': revision,
    'state': state.name,
    if (detail.isNotEmpty) 'detail': detail,
    if (scope.isNotEmpty) 'scope': scope,
  };
}

/// Why the technical labels do not apply to the running studio build.
enum CreatorEngineMismatch {
  /// The bundled manifest and the export carry the same build hash.
  none,

  /// The export has no build stamp: an old registry; nothing is known.
  exportWithoutStamp,

  /// The studio bundles no readable build manifest (hook not run).
  manifestMissing,

  /// SDK, runtime, compiler, resources, checks, surfaces or the contract
  /// changed since the registry was written.
  changed;

  String get label => switch (this) {
    none => '',
    exportWithoutStamp =>
      'El registro técnico no trae sello de motor: ejecuta readiness prepare.',
    manifestMissing =>
      'Sin manifiesto de build en el estudio: ejecuta compile_visuals.',
    changed => 'Cambió el motor compartido desde la comprobación.',
  };
}

class CreatorReadiness {
  const CreatorReadiness(
    this._entries, {
    this.generatedAt = '',
    this.engineBuildHash = '',
    this.engineSdkHash = '',
    this.engineAbi,
  });

  const CreatorReadiness.none()
    : _entries = const {},
      generatedAt = '',
      engineBuildHash = '',
      engineSdkHash = '',
      engineAbi = null;

  /// Parses `readiness/studio_readiness.json`; a malformed file means
  /// "unknown" for every visual, never a crash of the studio.
  factory CreatorReadiness.parse(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return const CreatorReadiness.none();
    }
    if (decoded is! Map<String, Object?> || decoded['schemaVersion'] != 1) {
      return const CreatorReadiness.none();
    }
    final visuals = decoded['visuals'];
    if (visuals is! Map<String, Object?>) return const CreatorReadiness.none();
    final engine = decoded['engine'];
    return CreatorReadiness(
      {
        for (final entry in visuals.entries)
          if (entry.value is Map<String, Object?>)
            entry.key: CreatorReadinessEntry.fromJson(
              entry.key,
              entry.value! as Map<String, Object?>,
            ),
      },
      generatedAt: decoded['generatedAt'] as String? ?? '',
      engineBuildHash:
          engine is Map ? (engine['buildHash'] as String? ?? '') : '',
      engineSdkHash: engine is Map ? (engine['sdkHash'] as String? ?? '') : '',
      engineAbi: engine is Map ? (engine['abi'] as num?)?.toInt() : null,
    );
  }

  final Map<String, CreatorReadinessEntry> _entries;
  final String generatedAt;

  /// Build manifest hash the export was generated against
  /// (`creator_build_manifest.dart`): SDK/ABI, runtime Swift, material
  /// compiler, resources, checks, surfaces and contract copy. The studio
  /// compares it with the manifest it bundles; any difference invalidates
  /// every technical label even when the vote revision is untouched.
  final String engineBuildHash;
  final String engineSdkHash;
  final int? engineAbi;

  /// How the running build relates to the export. Nothing is assumed: an
  /// export without a stamp or a studio without a manifest is unknown.
  CreatorEngineMismatch engineMismatch(String? bundledBuildHash) {
    if (engineBuildHash.isEmpty)
      return CreatorEngineMismatch.exportWithoutStamp;
    if (bundledBuildHash == null || bundledBuildHash.isEmpty) {
      return CreatorEngineMismatch.manifestMissing;
    }
    return bundledBuildHash == engineBuildHash
        ? CreatorEngineMismatch.none
        : CreatorEngineMismatch.changed;
  }

  bool get isEmpty => _entries.isEmpty;
  int get length => _entries.length;

  /// The entry for the visual as it is now: evidence of another revision
  /// does not apply (the drawing changed since it was checked).
  CreatorReadinessEntry entryFor(
    String id,
    String revision, {
    CreatorEngineMismatch engine = CreatorEngineMismatch.none,
  }) {
    if (engine != CreatorEngineMismatch.none) {
      return CreatorReadinessEntry(
        id: id,
        revision: revision,
        state: CreatorReadinessState.unknown,
        detail: engine.label,
      );
    }
    final entry = _entries[id];
    if (entry == null) {
      return CreatorReadinessEntry(
        id: id,
        revision: revision,
        state: CreatorReadinessState.unknown,
        detail: 'Sin registro técnico: ejecuta readiness prepare.',
      );
    }
    if (entry.revision != revision) {
      return CreatorReadinessEntry(
        id: id,
        revision: revision,
        state: CreatorReadinessState.unknown,
        detail: 'El dibujo cambió después de la última comprobación.',
      );
    }
    return entry;
  }

  int count(CreatorReadinessState state) =>
      _entries.values.where((entry) => entry.state == state).length;
}
