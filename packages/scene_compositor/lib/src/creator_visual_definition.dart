import 'dart:convert';

enum CreatorReactivity { none, music, optional }

enum CreatorRole { background, overlay }

enum CreatorPublication { draft, published }

class CreatorCredits {
  const CreatorCredits({this.author = '', this.license = '', this.source = ''});

  final String author;
  final String license;
  final String source;

  Map<String, String> toMap() => {
    'author': author,
    'license': license,
    'source': source,
  };
}

/// A frozen frame of the same shader, optionally replaced by a bundled image.
class CreatorThumbnailSpec {
  const CreatorThumbnailSpec({
    this.timeSeconds = 2.5,
    this.assetPath,
    this.assetPackage,
  });

  final double timeSeconds;
  final String? assetPath;
  final String? assetPackage;

  Map<String, Object> toMap() => {
    'timeSeconds': timeSeconds,
    if (assetPath != null) 'assetPath': assetPath!,
    if (assetPackage != null) 'assetPackage': assetPackage!,
  };
}

/// The SDK receives asset locations; it never imports an application's catalog.
class CreatorCatalogAssets {
  const CreatorCatalogAssets({
    required this.catalogAsset,
    required this.shaderAsset,
    required this.metadataAsset,
    this.assetPackage,
  });

  final String catalogAsset;
  final String shaderAsset;
  final String metadataAsset;
  final String? assetPackage;
}

class CreatorControls {
  const CreatorControls({
    this.intensity = 1,
    this.speed = 1,
    this.detail = 1,
    this.glow = 1,
  });

  final double intensity;
  final double speed;
  final double detail;
  final double glow;

  Map<String, double> toMap() => {
    'intensity': intensity,
    'speed': speed,
    'detail': detail,
    'glow': glow,
  };
}

/// One installed GPU program. The scene only references its stable [programId].
/// Source code is bundled at build time and never sent over the scene channel.
class CreatorVisualDefinition {
  const CreatorVisualDefinition({
    required this.id,
    required this.name,
    required this.shaderSource,
    this.description = '',
    this.purposes = const [],
    this.moods = const [],
    this.concepts = const [],
    this.credits = const CreatorCredits(),
    this.thumbnail = const CreatorThumbnailSpec(),
    this.publication = CreatorPublication.draft,
    this.role = CreatorRole.background,
    this.reactivity = CreatorReactivity.optional,
    this.framesPerSecond = 30,
    this.seed = 42,
    this.colors = const [0xff061427, 0xff00d5b1, 0xff6774ff, 0xffe9cbff],
    this.controls = const CreatorControls(),
  });

  final String id;
  final String name;
  final String shaderSource;
  final String description;
  final List<String> purposes;
  final List<String> moods;
  final List<String> concepts;
  final CreatorCredits credits;
  final CreatorThumbnailSpec thumbnail;
  final CreatorPublication publication;
  final CreatorRole role;
  final CreatorReactivity reactivity;
  final int framesPerSecond;
  final int seed;
  final List<int> colors;
  final CreatorControls controls;

  String get programId => 'creator_$id';

  Map<String, Object> toMetadata() => {
    'id': id,
    'name': name,
    'description': description,
    'purposes': purposes,
    'moods': moods,
    'concepts': concepts,
    'credits': credits.toMap(),
    'thumbnail': thumbnail.toMap(),
    'publication': publication.name,
    'role': role.name,
    'reactivity': reactivity.name,
  };

  Map<String, Object> toManifest() => {
    'id': id,
    'name': name,
    'programId': programId,
    'role': role.name,
    'reactivity': reactivity.name,
    'framesPerSecond': framesPerSecond,
    'seed': seed,
    'colors': colors,
    'controls': controls.toMap(),
    'shaderSource': shaderSource,
  };

  /// The production V1 owner already executes this restricted V2 descriptor.
  /// This does not enable the separate V2 rollout or embed executable source.
  Map<String, Object> sceneDocument({
    required double width,
    required double height,
    required bool reactive,
    int? qaSessionSeed,
  }) {
    if (!width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0 ||
        width > 8192 ||
        height > 8192) {
      throw ArgumentError('Invalid visual dimensions.');
    }
    if ((reactivity == CreatorReactivity.none && reactive) ||
        (reactivity == CreatorReactivity.music && !reactive)) {
      throw ArgumentError('Reactivity does not match $id.');
    }
    if (qaSessionSeed != null &&
        (qaSessionSeed < 0 || qaSessionSeed > 0xffffffff)) {
      throw ArgumentError(
        'The recording seed must fit uint32 without conversion.',
      );
    }
    const transform = <String, Object>{
      'width': 1.0,
      'height': 1.0,
      'offsetX': 0.0,
      'offsetY': 0.0,
      'scale': 1.0,
      'rotation': 0.0,
      'flipped': false,
    };
    final placement = <String, Object>{
      'id': id,
      'role': role.name,
      'opacity': 1.0,
      'blendMode': 'sourceOver',
      'alphaMode': 'normal',
      'transform': transform,
      'frameRateBinding': 'preferred',
      'preferredFramesPerSecond': framesPerSecond,
      'playbackRate': 1.0,
    };
    final inner = <String, Object>{
      'schemaVersion': 2,
      'sceneId': programId,
      'layers': [
        {
          ...placement,
          'fallbackPolicy': 'continuousCompatibility',
          'node': {
            'nodeType': 'effect.catalogProgram',
            'nodeVersion': 1,
            'parameters': {
              'programId': programId,
              'audioReactive': reactive,
              if (qaSessionSeed != null) 'seed': qaSessionSeed,
              'options': {...controls.toMap(), 'Music Reactive': reactive},
            },
            'resourceSlots': <Object>[],
            'signalBindings': [
              if (reactive)
                {
                  'signal': 'frame.v2',
                  'target': 'runtime.signalFrame',
                  'scale': 1.0,
                  'bias': 0.0,
                },
            ],
            'transitionStrategy': 'stateReplay',
            'qualityVariants': {
              for (final level in ['best', 'sustained', 'minimumFunctional'])
                level: {
                  'level': level,
                  'parameterOverrides': <String, Object>{},
                  'renderScale': 1.0,
                  'framesPerSecond': framesPerSecond,
                  'resourceOverrides': <String, Object>{},
                },
            },
          },
        },
      ],
    };
    return {
      'schemaVersion': 1,
      'sceneId': programId,
      'isAudioReactive': reactive,
      'layers': [
        {
          ...placement,
          'sourceKind': 'procedural',
          'proceduralPreset': 'native_program_v1',
          'proceduralParameters': {
            'document': inner,
            'resolvedResourcePaths': <String, String>{},
            'logicalWidth': width,
            'logicalHeight': height,
          },
          'audioReactive': reactive,
          'palette': colors,
        },
      ],
    };
  }
}

List<CreatorVisualDefinition> validateCreatorCatalog(
  List<CreatorVisualDefinition> visuals, {
  bool allowEmpty = false,
}) {
  if ((!allowEmpty && visuals.isEmpty) || visuals.length > 64) {
    throw const FormatException(
      'El catálogo debe tener entre 1 y 64 visuales.',
    );
  }
  final ids = <String>{};
  for (final visual in visuals) {
    void require(bool condition, String message) {
      if (!condition) throw FormatException('${visual.id}: $message');
    }

    require(
      RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(visual.id),
      'ID inválido.',
    );
    require(ids.add(visual.id), 'ID duplicado.');
    require(
      visual.name.trim().isNotEmpty && visual.name.length <= 100,
      'Nombre inválido.',
    );
    require(visual.framesPerSecond == 30, 'El presupuesto del kit es 30 FPS.');
    require(visual.description.length <= 2000, 'Descripción demasiado larga.');
    for (final tags in [visual.purposes, visual.moods, visual.concepts]) {
      require(
        tags.length <= 24 &&
            tags.every((tag) => tag.trim().isNotEmpty && tag.length <= 80) &&
            tags.map((tag) => tag.trim().toLowerCase()).toSet().length ==
                tags.length,
        'Las etiquetas deben ser únicas, no vacías y de hasta 80 caracteres (máximo 24).',
      );
    }
    for (final credit in visual.credits.toMap().entries) {
      require(
        credit.value.length <= 1000,
        'Crédito ${credit.key} demasiado largo.',
      );
    }
    final thumbnail = visual.thumbnail;
    require(
      thumbnail.timeSeconds.isFinite &&
          thumbnail.timeSeconds >= 0 &&
          thumbnail.timeSeconds <= 3600,
      'El fotograma de miniatura debe estar entre 0 y 3600 segundos.',
    );
    if (thumbnail.assetPath case final String path) {
      require(
        path.startsWith('assets/thumbnails/') &&
            path.split('/').length == 3 &&
            path.length <= 240 &&
            !path.split('/').contains('..') &&
            !path.contains('\\') &&
            RegExp(r'\.(png|jpe?g|webp)$', caseSensitive: false).hasMatch(path),
        'La miniatura debe ser una imagen relativa en assets/thumbnails/.',
      );
    }
    require(
      thumbnail.assetPackage == null ||
          thumbnail.assetPath != null &&
              RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(thumbnail.assetPackage!),
      'El paquete de miniatura requiere una ruta y un nombre de paquete válido.',
    );
    require(
      visual.seed >= 0 && visual.seed <= 0xffffffff,
      'Seed debe caber exactamente en uint32.',
    );
    require(
      visual.colors.length == 4 &&
          visual.colors.every((c) => c >= 0 && c <= 0xffffffff),
      'Usa cuatro colores ARGB.',
    );
    for (final entry in visual.controls.toMap().entries) {
      require(
        entry.value.isFinite &&
            entry.value >= (entry.key == 'detail' ? .25 : 0) &&
            entry.value <= 2,
        'Control ${entry.key} fuera de rango.',
      );
    }
    require(
      visual.shaderSource.contains('paintVisual') &&
          !visual.shaderSource.contains('#') &&
          !visual.shaderSource.contains('[[') &&
          utf8.encode(visual.shaderSource).length <= 65536,
      'Shader inválido: define paintVisual sin includes, atributos ni entrypoints.',
    );
  }
  if (utf8.encode(encodeCreatorCatalog(visuals)).length > 4 * 1024 * 1024) {
    throw const FormatException('El catálogo supera 4 MB.');
  }
  return List.unmodifiable(visuals);
}

String encodeCreatorCatalog(List<CreatorVisualDefinition> visuals) =>
    const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 1,
      'visuals': [for (final visual in visuals) visual.toManifest()],
    });
