import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:scene_compositor/authoring.dart';
import 'package:scene_compositor/creator_lint.dart';
import 'package:scene_compositor/native_compiler.dart';

// Pure Dart executable: `dart run test/creator_visual_definition_test.dart`.
void main() {
  _catalogAdmission();
  _documentContract();
  _reactivityContract();
  _modifiersContract();
  _frozenContract();
  _variationsContract();
  _lintContract();
  _paletteContract();
  stdout.writeln('scene_compositor: authoring contract checks passed.');
}

const _shader = '''
vec4 paintVisual(vec2 uv, CreatorFrame f) {
  return vec4(uv.x, uv.y, 0.2, 1.0);
}
''';

CreatorVisualDefinition _visual({
  String id = 'aurora',
  String name = 'Aurora',
  String shaderSource = _shader,
  CreatorReactivity reactivity = CreatorReactivity.optional,
  CreatorRole role = CreatorRole.background,
  int seed = 42,
  int fps = 30,
  List<int> colors = const [0xff000000, 0xff112233, 0xff445566, 0xffffffff],
  CreatorControls controls = const CreatorControls(),
}) => CreatorVisualDefinition(
  id: id,
  name: name,
  shaderSource: shaderSource,
  reactivity: reactivity,
  role: role,
  seed: seed,
  framesPerSecond: fps,
  colors: colors,
  controls: controls,
);

void _catalogAdmission() {
  final source = [_visual(), _visual(id: 'plasma')];
  final admitted = validateCreatorCatalog(source);
  source.clear();
  _expect(
    admitted.length == 2 && admitted.last.id == 'plasma',
    'stable catalog snapshot',
  );
  _throws<UnsupportedError>(() => admitted.add(_visual()), 'immutable catalog');
  _throws<FormatException>(() => validateCreatorCatalog([]), 'empty catalog');
  _throws<FormatException>(
    () => validateCreatorCatalog([_visual(), _visual()]),
    'duplicate IDs',
  );
  for (final id in [
    '',
    '1aurora',
    'with-dash',
    '../effect',
    'white space',
    'Äurora',
    'a' * 65,
  ]) {
    _throws<FormatException>(
      () => validateCreatorCatalog([_visual(id: id)]),
      'invalid ID $id',
    );
  }
  validateCreatorCatalog([_visual(id: 'a' * 64)]);
  _throws<FormatException>(
    () => validateCreatorCatalog([_visual(name: '  ')]),
    'empty name',
  );
  _throws<FormatException>(
    () => validateCreatorCatalog([_visual(name: 'a' * 101)]),
    'long name',
  );
  _throws<FormatException>(
    () => validateCreatorCatalog([_visual(fps: 45)]),
    'unsupported rendering budget',
  );
  validateCreatorCatalog([_visual(fps: 60)]);
  _throws<FormatException>(
    () => validateCreatorCatalog([_visual(seed: -1)]),
    'negative seed',
  );
  validateCreatorCatalog([_visual(seed: 0xffffffff)]);
  _throws<FormatException>(
    () => validateCreatorCatalog([_visual(seed: 0x100000000)]),
    'seed exceeds exact uint32 ABI',
  );
  _throws<FormatException>(
    () => validateCreatorCatalog([
      _visual(colors: [0, 1, 2]),
    ]),
    'palette length',
  );
  _throws<FormatException>(
    () => validateCreatorCatalog([
      _visual(colors: [0, 1, 2, 0x100000000]),
    ]),
    'palette range',
  );
  for (final controls in [
    const CreatorControls(intensity: double.nan),
    const CreatorControls(speed: double.infinity),
    const CreatorControls(glow: -0.1),
    const CreatorControls(detail: 0),
    const CreatorControls(intensity: 2.1),
  ]) {
    _throws<FormatException>(
      () => validateCreatorCatalog([_visual(controls: controls)]),
      'invalid controls',
    );
  }
  validateCreatorCatalog([
    _visual(
      controls: const CreatorControls(
        intensity: 0,
        speed: 0,
        detail: .25,
        glow: 2,
      ),
    ),
  ]);
  for (final source in [
    '',
    '#include <metal_stdlib>\n$_shader',
    '[[fragment]] $_shader',
    '${' ' * 65536}$_shader',
  ]) {
    _throws<FormatException>(
      () => validateCreatorCatalog([_visual(shaderSource: source)]),
      'invalid shader boundary',
    );
  }
  _throws<FormatException>(
    () => validateCreatorCatalog([
      for (var i = 0; i < 257; i++) _visual(id: 'visual_$i'),
    ]),
    'bounded catalog count',
  );
}

void _documentContract() {
  final visual = _visual(
    controls: const CreatorControls(
      intensity: .4,
      speed: .7,
      detail: .8,
      glow: .9,
    ),
  );
  final document = visual.sceneDocument(
    width: 390,
    height: 844,
    reactive: true,
    qaSessionSeed: 0xffffffff,
  );
  _expect(
    _keys(document, ['schemaVersion', 'sceneId', 'isAudioReactive', 'layers']),
    'strict production V1 envelope',
  );
  _expect(
    document['schemaVersion'] == 1 && document['sceneId'] == 'creator_aurora',
    'V1 owner and stable program identity',
  );
  final outer = _map((document['layers'] as List).single);
  _expect(
    outer['sourceKind'] == 'procedural' &&
        outer['proceduralPreset'] == 'native_program_v1',
    'existing production native source',
  );
  _expect(
    outer['preferredFramesPerSecond'] == 30 && outer['playbackRate'] == 1.0,
    'bounded cadence',
  );
  final parameters = _map(outer['proceduralParameters']);
  _expect(
    _keys(parameters, [
      'document',
      'resolvedResourcePaths',
      'logicalWidth',
      'logicalHeight',
    ]),
    'strict native program parameters',
  );
  _expect(
    parameters['logicalWidth'] == 390 && parameters['logicalHeight'] == 844,
    'logical size retained',
  );
  _expect(
    _map(parameters['resolvedResourcePaths']).isEmpty,
    'no undeclared resource loading',
  );
  final inner = _map(parameters['document']);
  _expect(
    inner['schemaVersion'] == 2 && inner['sceneId'] == visual.programId,
    'embedded compatible descriptor',
  );
  final layer = _map((inner['layers'] as List).single);
  _expect(
    layer['id'] == 'aurora' && layer['opacity'] == 1,
    'single native node identity',
  );
  final transform = _map(layer['transform']);
  _expect(
    transform['scale'] == 1 &&
        transform['offsetX'] == 0 &&
        transform['offsetY'] == 0,
    'identity transform',
  );
  final node = _map(layer['node']);
  _expect(
    node['nodeType'] == 'effect.catalogProgram' && node['nodeVersion'] == 1,
    'installed native catalog node',
  );
  _expect(
    (node['resourceSlots'] as List).isEmpty &&
        node['transitionStrategy'] == 'stateReplay',
    'no inferred media or restart policy',
  );
  final nodeParameters = _map(node['parameters']);
  _expect(
    nodeParameters['programId'] == visual.programId &&
        nodeParameters['audioReactive'] == true,
    'program and reactive route',
  );
  final options = _map(nodeParameters['options']);
  _expect(
    options['intensity'] == .4 &&
        options['speed'] == .7 &&
        options['detail'] == .8 &&
        options['glow'] == .9,
    'controls forwarded losslessly',
  );
  _expect(
    options['Music Reactive'] == true && nodeParameters['seed'] == 0xffffffff,
    'exact signal policy and capture seed',
  );
  final bindings = node['signalBindings'] as List;
  _expect(
    bindings.length == 1 &&
        _map(bindings.single)['signal'] == 'frame.v2' &&
        _map(bindings.single)['target'] == 'runtime.signalFrame',
    'exact production signal binding',
  );
  final variants = _map(node['qualityVariants']);
  _expect(
    _keys(variants, ['best', 'sustained', 'minimumFunctional']),
    'native quality levels',
  );
  for (final variant in variants.values) {
    _expect(
      _map(variant)['framesPerSecond'] == 30,
      'all variants respect budget',
    );
  }
  final serialized = jsonEncode(document);
  _expect(
    !serialized.contains('paintVisual') &&
        !serialized.contains('shaderSource') &&
        !serialized.contains('#include'),
    'no executable source sent through scene channel',
  );
  final manifest = jsonDecode(encodeCreatorCatalog([visual])) as Map;
  _expect(
    manifest['schemaVersion'] == 1 &&
        (manifest['visuals'] as List).single['shaderSource'] == _shader,
    'source exists only in build manifest',
  );
  for (final dimension in [0.0, -1.0, double.infinity, double.nan, 8193.0]) {
    _throws<ArgumentError>(
      () => visual.sceneDocument(width: dimension, height: 844, reactive: true),
      'invalid width',
    );
    _throws<ArgumentError>(
      () => visual.sceneDocument(width: 390, height: dimension, reactive: true),
      'invalid height',
    );
  }
  _throws<ArgumentError>(
    () => visual.sceneDocument(
      width: 390,
      height: 844,
      reactive: true,
      qaSessionSeed: 0x100000000,
    ),
    'unsupported capture seed rejected',
  );
}

void _reactivityContract() {
  for (final policy in CreatorReactivity.values) {
    final visual = _visual(reactivity: policy);
    for (final reactive in [false, true]) {
      final allowed =
          policy == CreatorReactivity.optional ||
          reactive == (policy == CreatorReactivity.music);
      if (!allowed) {
        _throws<ArgumentError>(
          () =>
              visual.sceneDocument(width: 320, height: 480, reactive: reactive),
          'policy mismatch $policy',
        );
        continue;
      }
      final document = visual.sceneDocument(
        width: 320,
        height: 480,
        reactive: reactive,
      );
      final outer = _map((document['layers'] as List).single);
      final inner = _map(_map(outer['proceduralParameters'])['document']);
      final node = _map(_map((inner['layers'] as List).single)['node']);
      _expect(
        document['isAudioReactive'] == reactive &&
            outer['audioReactive'] == reactive,
        'owner and layer agree',
      );
      _expect(
        (node['signalBindings'] as List).length == (reactive ? 1 : 0),
        'nonreactive program has no signal binding',
      );
    }
  }
  final overlay = _visual(
    role: CreatorRole.overlay,
  ).sceneDocument(width: 320, height: 480, reactive: false);
  _expect(
    _map((overlay['layers'] as List).single)['role'] == 'overlay',
    'overlay role preserved',
  );
}

Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value as Map);

bool _keys(Map<String, Object?> map, List<String> keys) =>
    map.length == keys.length && keys.every(map.containsKey);

const _galaxyModifiers = [
  CreatorModifier.steps('brazos', 'Brazos', min: 2, max: 6, value: 4),
  CreatorModifier.slider('giro', 'Giro', min: .2, max: 2, value: 1),
  CreatorModifier.toggle('nucleo', 'Núcleo', value: true),
  CreatorModifier.choice(
    'estilo',
    'Estilo',
    options: ['Auto', 'Nítido', 'Nebuloso'],
  ),
];

CreatorVisualDefinition _native({
  String id = 'galaxia',
  List<CreatorModifier> modifiers = _galaxyModifiers,
}) => CreatorVisualDefinition(
  id: id,
  name: 'Galaxia',
  nativeSource: 'class Visual final : public Scene {};',
  modifiers: modifiers,
);

void _modifiersContract() {
  final visual = validateCreatorCatalog([_native()]).single;
  final manifest = visual.toManifest();
  final declared = manifest['modifiers']! as List;
  _expect(declared.length == 4, 'manifest lists every modifier');
  _expect(
    jsonEncode(declared.first) ==
        jsonEncode({
          'id': 'brazos',
          'label': 'Brazos',
          'kind': 'steps',
          'min': 2.0,
          'max': 6.0,
          'value': 4.0,
        }),
    'a modifier is a typed number with its range',
  );
  _expect(
    jsonEncode(
          declared.last,
        ).contains('"options":["Auto","Nítido","Nebuloso"]') &&
        jsonEncode(declared.last).contains('"max":2.0'),
    'a choice sends its index; max is the last option',
  );
  _expect(
    !_native(
          id: 'plain',
          modifiers: const [],
        ).toManifest().containsKey('modifiers') &&
        !_visual().toManifest().containsKey('modifiers'),
    'catalogs without modifiers stay byte-identical',
  );
  _expect(
    visual.modifierDefaults.toString() ==
        {'brazos': 4.0, 'giro': 1.0, 'nucleo': 1.0, 'estilo': 0.0}.toString(),
    'defaults in declaration order; a toggle is 0/1',
  );

  // The runtime manifest decodes to the same visual, byte for byte.
  final runtime = encodeCreatorCatalog([visual]);
  final metadata = jsonEncode({
    'schemaVersion': 1,
    'visuals': [visual.toMetadata()],
  });
  final decoded =
      decodeCreatorCatalog(runtimeJson: runtime, metadataJson: metadata).single;
  _expect(
    jsonEncode(decoded.toManifest()) == jsonEncode(manifest),
    'modifiers round-trip through the catalog',
  );

  // Live values: unknown ids and values outside the range never pass.
  final resolved = visual.resolveModifiers({'giro': 1.5, 'estilo': 2});
  _expect(
    resolved['giro'] == 1.5 &&
        resolved['estilo'] == 2 &&
        resolved['brazos'] == 4,
    'live values override defaults',
  );
  for (final values in [
    {'brazos': 7.0},
    {'brazos': 3.5},
    {'giro': 2.1},
    {'nucleo': .5},
    {'estilo': 3.0},
    {'otro': 1.0},
    {'giro': double.nan},
  ]) {
    _throws<ArgumentError>(
      () => visual.resolveModifiers(values),
      'rejected live value $values',
    );
  }
  final options =
      ((((visual.sceneDocument(
                            width: 320,
                            height: 568,
                            reactive: true,
                          )['layers']
                          as List)
                      .single
                  as Map)['proceduralParameters']
              as Map)['document']
          as Map);
  final node = ((options['layers'] as List).single as Map)['node'] as Map;
  final sent = (node['parameters'] as Map)['options'] as Map;
  _expect(
    sent['brazos'] == 4.0 && sent['estilo'] == 0.0 && sent['speed'] == 1.0,
    'the scene document carries modifiers next to the basic controls',
  );

  // Invalid declarations are rejected with the visual's name.
  for (final (modifiers, reason) in [
    (
      [
        const CreatorModifier.slider(
          'speed',
          'Velocidad',
          min: 0,
          max: 1,
          value: .5,
        ),
      ],
      'reserved id',
    ),
    (
      [
        const CreatorModifier.slider(
          'class',
          'Clase',
          min: 0,
          max: 1,
          value: .5,
        ),
      ],
      'C++ keyword',
    ),
    (
      [const CreatorModifier.toggle('compl', 'Completo')],
      'C++ alternative token',
    ),
    ([const CreatorModifier.toggle('errno', 'Error')], 'lowercase macro'),
    ([const CreatorModifier.toggle('tamaño', 'Tamaño')], 'ñ in id'),
    (
      [
        const CreatorModifier.slider(
          'Ancho',
          'Ancho',
          min: 0,
          max: 1,
          value: .5,
        ),
      ],
      'uppercase id',
    ),
    (
      [const CreatorModifier.slider('ancho', '', min: 0, max: 1, value: .5)],
      'empty label',
    ),
    (
      [
        const CreatorModifier.slider(
          'ancho',
          'Un nombre visible larguísimo',
          min: 0,
          max: 1,
          value: .5,
        ),
      ],
      'long label',
    ),
    (
      [
        const CreatorModifier.slider(
          'ancho',
          'Ancho',
          min: 1,
          max: 1,
          value: 1,
        ),
      ],
      'empty range',
    ),
    (
      [
        const CreatorModifier.slider(
          'ancho',
          'Ancho',
          min: 0,
          max: 1,
          value: 2,
        ),
      ],
      'value outside range',
    ),
    (
      [
        const CreatorModifier.steps(
          'lados',
          'Lados',
          min: 0,
          max: 5000,
          value: 3,
        ),
      ],
      'too many steps',
    ),
    (
      [
        const CreatorModifier.choice('modo', 'Modo', options: ['Único']),
      ],
      'one option',
    ),
    (
      [
        const CreatorModifier.choice('modo', 'Modo', options: ['A', 'A']),
      ],
      'repeated option',
    ),
    (
      [
        const CreatorModifier.choice(
          'modo',
          'Modo',
          options: ['A', 'B'],
          value: 2,
        ),
      ],
      'index outside options',
    ),
    (
      [
        const CreatorModifier.toggle('borde', 'Borde'),
        const CreatorModifier.toggle('borde', 'Borde 2'),
      ],
      'repeated id',
    ),
    (
      [for (var i = 0; i < 9; i++) CreatorModifier.toggle('m$i', 'M $i')],
      'more than 8',
    ),
  ]) {
    _throws<FormatException>(
      () => validateCreatorCatalog([_native(modifiers: modifiers)]),
      reason,
    );
  }
  _throws<FormatException>(
    () => validateCreatorCatalog([
      CreatorVisualDefinition(
        id: 'legacy',
        name: 'Legacy',
        shaderSource: _shader,
        modifiers: const [CreatorModifier.toggle('borde', 'Borde')],
      ),
    ]),
    'shader visuals have no modifiers',
  );
}

void _variationsContract() {
  CreatorVisualDefinition withVariations(List<CreatorVariation> variations) =>
      CreatorVisualDefinition(
        id: 'galaxia',
        name: 'Galaxia',
        nativeSource: 'class Visual final : public Scene {};',
        modifiers: _galaxyModifiers,
        variations: variations,
      );
  const tormenta = CreatorVariation('Tormenta', {
    'brazos': 6,
    'estilo': 'Nebuloso',
    'nucleo': false,
    'speed': 1.4,
  });
  final visual =
      validateCreatorCatalog([
        withVariations(const [tormenta]),
      ]).single;
  final resolved = tormenta.resolve(visual);
  _expect(
    resolved.modifiers.toString() ==
            {
              'brazos': 6.0,
              'giro': 1.0,
              'nucleo': 0.0,
              'estilo': 2.0,
            }.toString() &&
        resolved.controls.speed == 1.4 &&
        resolved.controls.intensity == 1,
    'a variation resolves choices by text and keeps the rest initial',
  );
  _expect(
    !visual.toManifest().containsKey('variations') &&
        jsonEncode(visual.toManifest()) == jsonEncode(_native().toManifest()),
    'variations never reach the engine manifest',
  );
  final metadata = visual.toMetadata();
  _expect(
    jsonEncode(metadata['variations']) ==
        jsonEncode([
          {
            'name': 'Tormenta',
            'values': {
              'brazos': 6,
              'estilo': 'Nebuloso',
              'nucleo': false,
              'speed': 1.4,
            },
          },
        ]),
    'metadata keeps what the author wrote',
  );
  _expect(
    !_native().toMetadata().containsKey('variations'),
    'metadata without variations stays byte-identical',
  );
  final decoded =
      decodeCreatorCatalog(
        runtimeJson: encodeCreatorCatalog([visual]),
        metadataJson: jsonEncode({
          'schemaVersion': 1,
          'visuals': [metadata],
        }),
      ).single;
  _expect(
    jsonEncode(decoded.toMetadata()) == jsonEncode(metadata),
    'variations round-trip through the metadata',
  );

  for (final (variations, reason) in [
    (
      const [
        CreatorVariation('Rara', {'otro': 1}),
      ],
      'unknown key',
    ),
    (
      const [
        CreatorVariation('Rara', {'estilo': 'Brillante'}),
      ],
      'missing option',
    ),
    (
      const [
        CreatorVariation('Rara', {'brazos': 9}),
      ],
      'out of range',
    ),
    (
      const [
        CreatorVariation('Rara', {'brazos': 3.5}),
      ],
      'steps not whole',
    ),
    (
      const [
        CreatorVariation('Rara', {'nucleo': 1}),
      ],
      'toggle needs a bool',
    ),
    (
      const [
        CreatorVariation('Rara', {'speed': 3}),
      ],
      'basic out of range',
    ),
    (
      const [
        CreatorVariation('Rara', {'detail': .1}),
      ],
      'detail below .25',
    ),
    (const [CreatorVariation('Rara', {})], 'empty'),
    (
      const [
        CreatorVariation('Rara', {'brazos': 4}),
      ],
      'equal to the original',
    ),
    (
      const [
        CreatorVariation('original', {'brazos': 3}),
      ],
      'named Original',
    ),
    (
      const [
        CreatorVariation('', {'brazos': 3}),
      ],
      'empty name',
    ),
    (
      const [
        CreatorVariation('Un nombre muy muy largo', {'brazos': 3}),
      ],
      'long name',
    ),
    (
      const [
        CreatorVariation('Calma', {'brazos': 3}),
        CreatorVariation('calma', {'brazos': 5}),
      ],
      'repeated name',
    ),
    (
      [
        for (var i = 0; i < 5; i++)
          CreatorVariation('V$i', {'brazos': 2 + i % 3}),
      ],
      'more than 4',
    ),
  ]) {
    _throws<FormatException>(
      () => validateCreatorCatalog([withVariations(variations)]),
      'variation rejected: $reason',
    );
  }
}

void _paletteContract() {
  final visual = validateCreatorCatalog([_native()]).single;
  Map<String, dynamic> options(Map<String, Object> document) =>
      (((((document['layers'] as List).single as Map)['proceduralParameters']
                      as Map)['document']
                  as Map)['layers']
              as List)
          .single['node']['parameters']['options'];
  final plain = options(
    visual.sceneDocument(width: 1, height: 1, reactive: true),
  );
  _expect(
    !plain.keys.any((k) => k.startsWith('color')),
    'documents without a live palette carry no color keys',
  );
  final painted = options(
    visual.sceneDocument(
      width: 1,
      height: 1,
      reactive: true,
      livePalette: const [0xff000000, 0xff00ffff, 0xffff00ff, 0x00000000],
    ),
  );
  _expect(
    painted['color1'] == 0xff00ffff && painted['color3'] == 0,
    'a live palette travels as four ARGB options',
  );
  for (final bad in [
    const [1, 2, 3],
    const [0, 0, 0, 0x100000000],
    const [0, 0, 0, -1],
  ]) {
    _throws<ArgumentError>(
      () => visual.sceneDocument(
        width: 1,
        height: 1,
        reactive: true,
        livePalette: bad,
      ),
      'invalid palette $bad',
    );
  }
  _throws<ArgumentError>(
    () => validateCreatorPalette(_visual(), const [0, 0, 0, 0]),
    'shader visuals have no live palette',
  );
  _throws<FormatException>(
    () => validateCreatorCatalog([
      _native(modifiers: const [CreatorModifier.toggle('color1', 'Color')]),
    ]),
    'palette keys are reserved',
  );
}

void _lintContract() {
  List<String> lint(String source, {String label = 'Brazos'}) =>
      lintCreatorVisual(
        CreatorVisualDefinition(
          id: 'galaxia',
          name: 'Galaxia',
          nativeSource: source,
          sourceFile: 'galaxia.dart',
          modifiers: [
            CreatorModifier.steps('brazos', label, min: 2, max: 6, value: 4),
          ],
        ),
      );
  _expect(lint('auto m = modifiers(f); draw(m.brazos);').isEmpty, 'used id');
  _expect(lint('auto g = glide(f); arms(g.brazos);').isEmpty, 'glide counts');
  final unused = lint('class Visual final : public Scene {};');
  _expect(
    unused.single.contains('galaxia.dart') &&
        unused.single.contains('(brazos) no se usa'),
    'an unused modifier names the file and the id',
  );
  _expect(
    lint(
      '// m.brazos\nauto s = "m.brazos"; /* .brazos */ char c = \'.\';',
    ).single.contains('no se usa'),
    'a name only in comments or strings does not count',
  );
  _expect(
    lint(
      'float a = f.modifiers[0] + m.brazos;',
    ).single.contains('f.modifiers[…]'),
    'raw access is refused',
  );
  _expect(
    lint('m.brazos', label: 'Velocidad').single.contains('ajuste básico'),
    'a label that renames a basic is refused',
  );
  _expect(
    lint('m.brazos', label: 'Brillo del núcleo').isEmpty,
    'a label that only mentions a basic is fine',
  );
  _expect(
    lintCreatorVisual(
      const CreatorVisualDefinition(id: 'a', name: 'A', nativeSource: 'x'),
    ).isEmpty,
    'visuals without modifiers have nothing to check',
  );
}

/// Digest of the C++ generated for [_native] per [creatorGlideRuntime]. A
/// generator change must bump the runtime, so old binaries never match.
const _glideGolden = {
  1: 'c79f8936b824beca0c9e4fe690b6631bee44116aa4186d8335c7a8bf41c55005',
};

void _frozenContract() {
  final swift =
      File.fromUri(
        Platform.script.resolve(
          '../ios/Classes/Runtime/SceneCatalogCreatorRegistry.swift',
        ),
      ).readAsStringSync();
  Set<String> swiftKeys(String name) => {
    for (final match in RegExp(r'"([^"]+)"').allMatches(
      RegExp('let $name: Set<String> = \\[([^\\]]*)\\]').firstMatch(swift)![1]!,
    ))
      match[1]!,
  };
  final modifierKeys = swiftKeys('keys');
  for (final modifier in _galaxyModifiers) {
    final keys = modifier.toMap().keys.toSet();
    final expected = {
      ...modifierKeys,
      if (modifier.kind == CreatorModifierKind.choice) 'options',
    };
    _expect(
      keys.length == expected.length && keys.containsAll(expected),
      'modifier ${modifier.id} keys match the iOS decoder exactly',
    );
  }
  final manifest = _native().toManifest().keys.toSet()..remove('modifiers');
  final native = {
    ...swiftKeys('baseKeys'),
    'kind',
    'nativeSource',
    'shaderSources',
    'images',
    'nativeBuild',
  };
  _expect(
    native.containsAll(manifest) &&
        native.difference(manifest).every((key) => key == 'nativeBuild'),
    'native manifest keys are the ones the iOS decoder accepts '
    '(UI-only attributes belong in toMetadata)',
  );

  final visual = validateCreatorCatalog([_native()]).single;
  final generated = [
    creatorModifierReader(visual),
    creatorGlideReader(visual),
    creatorGlideWrapper(visual),
  ].join('\n');
  final digest = sha256.convert(utf8.encode(generated)).toString();
  _expect(
    _glideGolden[creatorGlideRuntime] == digest,
    'the generated C++ changed: bump creatorGlideRuntime and set '
    '_glideGolden[$creatorGlideRuntime] = $digest',
  );
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('Failed: $message');
}

void _throws<T extends Object>(void Function() action, String message) {
  try {
    action();
  } catch (error) {
    if (error is T) return;
    rethrow;
  }
  throw StateError('Expected $T: $message');
}
