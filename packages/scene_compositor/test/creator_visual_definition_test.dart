import 'dart:convert';
import 'dart:io';

import 'package:scene_compositor/authoring.dart';

// Pure Dart executable: `dart run test/creator_visual_definition_test.dart`.
void main() {
  _catalogAdmission();
  _documentContract();
  _reactivityContract();
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
      for (var i = 0; i < 65; i++) _visual(id: 'visual_$i'),
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
