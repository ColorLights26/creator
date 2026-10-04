import 'dart:convert';

import 'creator_variation.dart';

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

  void validate() {
    if (![
          intensity,
          speed,
          detail,
          glow,
        ].every((v) => v.isFinite && v >= 0 && v <= 2) ||
        detail < .25) {
      throw ArgumentError(
        'Controls must be finite: intensity/speed/glow 0–2, detail .25–2.',
      );
    }
  }

  Map<String, double> toMap() => {
    'intensity': intensity,
    'speed': speed,
    'detail': detail,
    'glow': glow,
  };
}

enum CreatorModifierKind { slider, steps, toggle, choice }

/// A setting the author exposes for one visual. It is declared next to the
/// C++ code that reads it (`modifiers(f).<id>`), shown under Ajustes in the
/// studio and sent to the engine as one number: the slider value, the step,
/// 0/1 for a toggle or the index of the chosen option.
class CreatorModifier {
  /// A decimal value between [min] and [max].
  const CreatorModifier.slider(
    this.id,
    this.label, {
    required this.min,
    required this.max,
    required this.value,
  }) : kind = CreatorModifierKind.slider,
       options = const [];

  /// A whole number between [min] and [max] (counts, symmetry, segments).
  const CreatorModifier.steps(
    this.id,
    this.label, {
    required int this.min,
    required int this.max,
    required int this.value,
  }) : kind = CreatorModifierKind.steps,
       options = const [];

  /// On or off.
  const CreatorModifier.toggle(this.id, this.label, {bool value = false})
    : kind = CreatorModifierKind.toggle,
      min = 0,
      max = 1,
      value = value ? 1 : 0,
      options = const [];

  /// One of [options]; the code receives its index. Put "Auto" first when the
  /// visual already changes on its own.
  const CreatorModifier.choice(
    this.id,
    this.label, {
    required this.options,
    int this.value = 0,
  }) : kind = CreatorModifierKind.choice,
       min = 0,
       max = -1;

  /// Snake case: also the field name in C++.
  final String id;

  /// Spanish, shown in the studio.
  final String label;
  final CreatorModifierKind kind;
  final num min;
  final num max;
  final num value;
  final List<String> options;

  double get lower => kind == CreatorModifierKind.choice ? 0 : min.toDouble();
  double get upper =>
      kind == CreatorModifierKind.choice
          ? (options.length - 1).toDouble()
          : max.toDouble();

  /// Whether [candidate] is a value the engine accepts for this modifier.
  bool accepts(double candidate) =>
      candidate.isFinite &&
      candidate >= lower &&
      candidate <= upper &&
      (kind == CreatorModifierKind.slider ||
          candidate == candidate.roundToDouble());

  Map<String, Object> toMap() => {
    'id': id,
    'label': label,
    'kind': kind.name,
    'min': lower,
    'max': upper,
    'value': value.toDouble(),
    if (kind == CreatorModifierKind.choice) 'options': options,
  };
}

/// Names the engine already uses for every visual, plus every C++ keyword,
/// alternative token and lowercase macro that cannot be a field name.
const creatorReservedModifierIds = {
  'intensity',
  'speed',
  'detail',
  'glow',
  'colors',
  'palette',
  'music',
  'music_reactive',
  'time',
  'delta',
  'width',
  'height',
  'seed',
  'modifiers',
  'glide',
  'color0',
  'color1',
  'color2',
  'color3',
  'alignas',
  'alignof',
  'and',
  'and_eq',
  'asm',
  'auto',
  'bitand',
  'bitor',
  'bool',
  'break',
  'case',
  'catch',
  'char',
  'char8_t',
  'char16_t',
  'char32_t',
  'class',
  'compl',
  'concept',
  'const',
  'const_cast',
  'consteval',
  'constexpr',
  'constinit',
  'continue',
  'co_await',
  'co_return',
  'co_yield',
  'decltype',
  'default',
  'delete',
  'do',
  'double',
  'dynamic_cast',
  'else',
  'enum',
  'explicit',
  'export',
  'extern',
  'false',
  'float',
  'for',
  'friend',
  'goto',
  'if',
  'inline',
  'int',
  'long',
  'mutable',
  'namespace',
  'new',
  'noexcept',
  'not',
  'not_eq',
  'nullptr',
  'operator',
  'or',
  'or_eq',
  'private',
  'protected',
  'public',
  'register',
  'reinterpret_cast',
  'requires',
  'return',
  'short',
  'signed',
  'sizeof',
  'static',
  'static_assert',
  'static_cast',
  'struct',
  'switch',
  'template',
  'this',
  'thread_local',
  'throw',
  'true',
  'try',
  'typedef',
  'typeid',
  'typename',
  'union',
  'unsigned',
  'using',
  'virtual',
  'void',
  'volatile',
  'wchar_t',
  'while',
  'xor',
  'xor_eq',
  'errno',
  'assert',
  'offsetof',
  'stdin',
  'stdout',
  'stderr',
};

/// A palette that may replace [visual]'s four colors live (Studio's palette
/// row): four ARGB colors, only for native visuals.
void validateCreatorPalette(CreatorVisualDefinition visual, List<int> palette) {
  if (!visual.isNative ||
      palette.length != 4 ||
      !palette.every((color) => color >= 0 && color <= 0xffffffff)) {
    throw ArgumentError('A live palette is four ARGB colors of a native visual.');
  }
}

/// At most this many modifiers per visual; the engine reserves the slots.
const creatorMaximumModifiers = 8;

/// One installed GPU program. The scene only references its stable [programId].
/// Source code is bundled at build time and never sent over the scene channel.
class CreatorVisualDefinition {
  const CreatorVisualDefinition({
    required this.id,
    required this.name,
    this.shaderSource = '',
    this.nativeSource = '',
    this.shaderSources = const {},
    this.images = const {},
    this.nativeBuild = const {},
    this.sourceFile = 'visual.dart',
    this.sourceLine = 1,
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
    this.modifiers = const [],
    this.variations = const [],
  });

  final String id;
  final String name;
  final String shaderSource;
  final String nativeSource;
  final Map<String, String> shaderSources;
  final Map<String, String> images;
  final Map<String, dynamic> nativeBuild;
  final String sourceFile;
  final int sourceLine;
  bool get isNative => nativeSource.isNotEmpty;
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

  /// Settings the author exposes, declared next to the C++ code.
  final List<CreatorModifier> modifiers;

  /// Named looks the author declares (Studio chips). Metadata only: they
  /// never change the engine program, its hash or the team's votes.
  final List<CreatorVariation> variations;

  String get programId => 'creator_$id';

  /// Default value of every modifier, by id, in declaration order.
  Map<String, double> get modifierDefaults => {
    for (final modifier in modifiers) modifier.id: modifier.value.toDouble(),
  };

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
    if (variations.isNotEmpty)
      'variations': [for (final variation in variations) variation.toMap()],
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
    // Only when declared: catalogs without modifiers stay byte-identical.
    if (modifiers.isNotEmpty)
      'modifiers': [for (final modifier in modifiers) modifier.toMap()],
    'shaderSource': shaderSource,
    if (isNative) ...{
      'kind': 'scene',
      'nativeSource': nativeSource,
      'shaderSources': shaderSources,
      'images': images,
      'nativeBuild': nativeBuild,
    },
  };

  /// The production V1 owner already executes this restricted V2 descriptor.
  /// This does not enable the separate V2 rollout or embed executable source.
  Map<String, Object> sceneDocument({
    required double width,
    required double height,
    required bool reactive,
    int? qaSessionSeed,
    CreatorControls? liveControls,
    Map<String, double>? liveModifiers,
    List<int>? livePalette,
  }) {
    final effectiveControls = liveControls ?? controls;
    effectiveControls.validate();
    final effectiveModifiers = resolveModifiers(liveModifiers);
    if (livePalette != null) validateCreatorPalette(this, livePalette);
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
              'options': {
                ...effectiveControls.toMap(),
                ...effectiveModifiers,
                // Only while a live palette replaces the catalog colors.
                if (livePalette != null)
                  for (var i = 0; i < 4; i++) 'color$i': livePalette[i],
                'Music Reactive': reactive,
              },
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

  /// Every modifier with its default, overridden by [values]. Unknown ids or
  /// values outside a modifier's range are rejected, never ignored.
  Map<String, double> resolveModifiers(Map<String, double>? values) {
    final resolved = modifierDefaults;
    for (final MapEntry(:key, :value) in (values ?? const {}).entries) {
      final modifier = modifiers.where((m) => m.id == key).firstOrNull;
      if (modifier == null) {
        throw ArgumentError('$id no tiene el modificador $key.');
      }
      if (!modifier.accepts(value)) {
        throw ArgumentError('$key: $value está fuera de su rango.');
      }
      resolved[key] = value;
    }
    return resolved;
  }
}

/// Topes del catálogo. Sólo frenan un archivo corrupto o desbocado; no limitan
/// cuántos visuales puede reunir un estudio.
const maxCreatorCatalogVisuals = 100000;
const maxCreatorCatalogBytes = 256 * 1024 * 1024;
const maxCreatorMetadataBytes = 64 * 1024 * 1024;

List<CreatorVisualDefinition> validateCreatorCatalog(
  List<CreatorVisualDefinition> visuals, {
  bool allowEmpty = false,
}) {
  if ((!allowEmpty && visuals.isEmpty) ||
      visuals.length > maxCreatorCatalogVisuals) {
    throw const FormatException(
      'El catálogo debe tener entre 1 y $maxCreatorCatalogVisuals visuales.',
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
    require([30, 60].contains(visual.framesPerSecond), 'Solicita 30 o 60 FPS.');
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
    _validateModifiers(visual, require);
    validateCreatorVariations(visual, require);
    if (visual.isNative) {
      require(
        visual.shaderSource.isEmpty,
        'Usa nativeSource o shaderSource, no ambos.',
      );
      require(
        utf8.encode(visual.nativeSource).length <= 256 * 1024,
        'Programa mayor de 256 KiB.',
      );
      require(
        visual.shaderSources.length <= 16 && visual.images.length <= 16,
        'Máximo 16 materiales y 16 imágenes.',
      );
      for (final name in [
        ...visual.shaderSources.keys,
        ...visual.images.keys,
      ]) {
        require(
          RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(name),
          'Nombre de recurso inválido.',
        );
      }
      for (final source in visual.shaderSources.values) {
        require(
          utf8.encode(source).length <= 256 * 1024,
          'Material mayor de 256 KiB.',
        );
      }
      for (final path in visual.images.values) {
        require(
          RegExp(
            r'^assets/images/[a-zA-Z0-9_-]+\.(png|jpg|jpeg|webp)$',
          ).hasMatch(path),
          'Las imágenes deben vivir en assets/images/ con un nombre simple.',
        );
      }
    } else
      require(
        visual.shaderSource.contains('paintVisual') &&
            !visual.shaderSource.contains('#') &&
            !visual.shaderSource.contains('[[') &&
            utf8.encode(visual.shaderSource).length <= 65536,
        'Shader inválido: define paintVisual sin includes, atributos ni entrypoints.',
      );
  }
  if (utf8.encode(encodeCreatorCatalog(visuals)).length >
      maxCreatorCatalogBytes) {
    throw const FormatException('El catálogo supera 256 MB.');
  }
  return List.unmodifiable(visuals);
}

void _validateModifiers(
  CreatorVisualDefinition visual,
  void Function(bool condition, String message) require,
) {
  final modifiers = visual.modifiers;
  if (modifiers.isEmpty) return;
  require(
    visual.isNative,
    'Los modificadores sólo existen en visuales con nativeSource.',
  );
  require(
    modifiers.length <= creatorMaximumModifiers,
    'Máximo $creatorMaximumModifiers modificadores.',
  );
  final ids = <String>{};
  for (final modifier in modifiers) {
    final name = modifier.id;
    require(
      RegExp(r'^[a-z][a-z0-9_]{0,23}$').hasMatch(name),
      'Modificador $name: usa letras a-z sin acentos ni ñ, números y _; '
      'empieza por letra (hasta 24 caracteres).',
    );
    require(ids.add(name), 'Modificador $name repetido.');
    require(
      !creatorReservedModifierIds.contains(name),
      'Modificador $name: ese nombre está reservado, elige otro.',
    );
    require(
      modifier.label.trim().isNotEmpty && modifier.label.length <= 24,
      'Modificador $name: el nombre visible debe tener de 1 a 24 caracteres.',
    );
    switch (modifier.kind) {
      case CreatorModifierKind.slider:
      case CreatorModifierKind.steps:
        require(
          modifier.min.isFinite &&
              modifier.max.isFinite &&
              modifier.min.abs() <= 100000 &&
              modifier.max.abs() <= 100000 &&
              modifier.min < modifier.max,
          'Modificador $name: min debe ser menor que max (hasta ±100000).',
        );
        if (modifier.kind == CreatorModifierKind.steps) {
          require(
            modifier.max - modifier.min <= 1000,
            'Modificador $name: como mucho 1000 pasos.',
          );
        }
      case CreatorModifierKind.toggle:
        break;
      case CreatorModifierKind.choice:
        require(
          modifier.options.length >= 2 &&
              modifier.options.length <= 8 &&
              modifier.options.every(
                (option) => option.trim().isNotEmpty && option.length <= 20,
              ) &&
              modifier.options.toSet().length == modifier.options.length,
          'Modificador $name: de 2 a 8 opciones distintas, de hasta 20 caracteres.',
        );
    }
    require(
      modifier.accepts(modifier.value.toDouble()),
      'Modificador $name: el valor inicial está fuera de su rango.',
    );
  }
}

String encodeCreatorCatalog(List<CreatorVisualDefinition> visuals) =>
    const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 1,
      'visuals': [for (final visual in visuals) visual.toManifest()],
    });
