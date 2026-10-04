import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/compile_visuals.dart';

void main() {
  late Directory catalog;
  late Directory visuals;

  setUp(() {
    catalog = Directory.systemTemp.createTempSync('creator-registry-');
    visuals = Directory('${catalog.path}/lib/visuals')
      ..createSync(recursive: true);
  });
  tearDown(() => catalog.deleteSync(recursive: true));

  void writePair(String name) {
    File('${visuals.path}/$name.dart').writeAsStringSync(
      "const shaderSource = r'''vec4 paintVisual(vec2 uv, CreatorFrame f) { return vec4(1.0); }''';",
    );
    File('${visuals.path}/${name}_metadata.dart').writeAsStringSync(
      "import 'package:scene_compositor/authoring.dart';\nconst metadata = CreatorVisualMetadata(id: '$name', name: '$name');",
    );
  }

  test(
    'adding a source pair automatically updates the deterministic registry',
    () {
      writePair('zeta');
      writePair('alpha');
      writeCreatorRegistry(catalog);
      final registry = File('${catalog.path}/lib/src/registry.g.dart');
      final first = registry.readAsStringSync();
      expect(first.indexOf('alpha.dart'), lessThan(first.indexOf('zeta.dart')));
      expect(first, contains('final creatorSourceVisuals'));
      expect(
        first,
        contains('metadata_1.metadata.withShader(visual_1.shaderSource)'),
      );

      writePair('middle');
      writeCreatorRegistry(catalog);
      final next = registry.readAsStringSync();
      expect(next, contains("import '../visuals/middle.dart' as visual_1;"));
      expect(next, contains("import '../visuals/zeta.dart' as visual_2;"));
      expect(
        next,
        contains('metadata_2.metadata.withShader(visual_2.shaderSource)'),
      );
      writeCreatorRegistry(catalog);
      expect(registry.readAsStringSync(), next);
    },
  );

  test('templates outside the visuals directory are not registered', () {
    File(
      '${catalog.path}/lib/visual_template.dart',
    ).writeAsStringSync('template');
    writePair('aurora');
    expect(
      generateCreatorRegistry(visuals),
      isNot(contains('visual_template')),
    );
  });

  test('missing metadata fails with the exact companion filename', () {
    File(
      '${visuals.path}/olas.dart',
    ).writeAsStringSync('const shaderSource = "";');
    expect(
      () => generateCreatorRegistry(visuals),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('olas_metadata.dart'),
        ),
      ),
    );
  });

  test('orphan metadata cannot become a visual silently', () {
    File(
      '${visuals.path}/olas_metadata.dart',
    ).writeAsStringSync('const metadata = null;');
    expect(
      () => generateCreatorRegistry(visuals),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('olas.dart'),
        ),
      ),
    );
  });

  test('a large catalog is accepted beyond the old 256-pair limit', () {
    for (var i = 0; i < 300; i++) {
      writePair('visual_$i');
    }
    expect(generateCreatorRegistry(visuals), contains('metadata_299.metadata'));
  });

  test('a symlink cannot silently import source outside the catalog', () {
    final source = File('${catalog.path}/external.dart')
      ..writeAsStringSync('source');
    Link('${visuals.path}/external.dart').createSync(source.path);
    expect(() => generateCreatorRegistry(visuals), throwsFormatException);
  });

  test('common AI paste mistakes fail before replacing the registry', () {
    writePair('valid');
    writeCreatorRegistry(catalog);
    final registry = File('${catalog.path}/lib/src/registry.g.dart');
    final previous = registry.readAsStringSync();
    writePair('olas');
    final source = File('${visuals.path}/olas.dart');
    final good = source.readAsStringSync();
    for (final bad in [
      '```dart\n$good\n```',
      '<html><canvas></canvas></html>',
      'import "package:flutter/material.dart"; void main() {}',
      'vec4 paintVisual(vec2 uv, CreatorFrame f) { return vec4(1.0); }',
      '$good\nfinal extra = 1;',
    ]) {
      source.writeAsStringSync(bad);
      expect(
        () => writeCreatorRegistry(catalog),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('olas.dart'),
          ),
        ),
      );
      expect(registry.readAsStringSync(), previous);
    }
  });

  test('metadata mixed with executable code identifies the separate file', () {
    writePair('olas');
    final file = File('${visuals.path}/olas_metadata.dart');
    file.writeAsStringSync('${file.readAsStringSync()}\nvoid main() {}');
    expect(
      () => generateCreatorRegistry(visuals),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('olas_metadata.dart'),
        ),
      ),
    );
  });

  group('modifiers', () {
    const authoring = "import 'package:scene_compositor/authoring.dart';";
    const list = '''const modifiers = [
  CreatorModifier.steps('lados', 'Lados (n)', min: 3, max: 12, value: 6),
  CreatorModifier.slider('zoom', 'Zoom [x]', min: .5, max: 2, value: 1),
  CreatorModifier.toggle('borde', 'Borde', value: true),
  CreatorModifier.choice('modo', 'Modo', options: ['Auto', 'Ola', 'Rayo']),
];''';
    const native =
        "const nativeSource = r'''class Visual final : public Scene {};''';";

    void writeNative(String name, String code) {
      writePair(name);
      File('${visuals.path}/$name.dart').writeAsStringSync(code);
    }

    Matcher failsNaming(String file, String reason) => throwsA(
      isA<FormatException>().having(
        (e) => e.message,
        'message',
        allOf(contains(file), contains(reason)),
      ),
    );

    test('a declared list reaches the registry next to nativeSource', () {
      writeNative('olas', '$authoring\n\n$list\n\n$native\n');
      writeNative('lisa', '$native\n');
      final registry = generateCreatorRegistry(visuals);
      expect(
        registry,
        contains(
          'withNative(visual_1.nativeSource, shaderSources: const {}, '
          'modifiers: visual_1.modifiers, ',
        ),
      );
      expect(
        registry,
        contains(
          'withNative(visual_0.nativeSource, shaderSources: const {}, '
          "sourceFile: 'lisa.dart'",
        ),
      );
    });

    test('numbers may use exponents, hex and digit separators', () {
      writeNative(
        'olas',
        "$authoring\nconst modifiers = [\n"
            "  CreatorModifier.slider('a', 'A', min: 1e-3, max: 2E1, value: 1),\n"
            "  CreatorModifier.steps('b', 'B', min: 0x2, max: 1_000, value: 10),\n"
            "];\n$native",
      );
      expect(
        generateCreatorRegistry(visuals),
        contains('modifiers: visual_0.modifiers'),
      );
    });

    test('the import and the list only travel together', () {
      writeNative('olas', '$list\n$native');
      expect(
        () => generateCreatorRegistry(visuals),
        failsNaming('olas.dart', 'import'),
      );
      writeNative('olas', '$authoring\n$native');
      expect(
        () => generateCreatorRegistry(visuals),
        failsNaming('olas.dart', 'const modifiers'),
      );
    });

    test('only literal declarations pass; nothing runs during discovery', () {
      for (final (bad, reason) in [
        (
          "CreatorModifier.slider('a', 'A', min: lerp(0, 1), max: 2, value: 1),",
          'lerp',
        ),
        ("CreatorModifier.toggle('a', 'A'); final x = 1;", 'final'),
        (r"CreatorModifier.toggle('a', 'A ${1 + 1}'),", r'$'),
        (
          "CreatorModifier.toggle('a', 'A'),\n];\nconst otro = [",
          'nativeSource',
        ),
      ]) {
        writeNative(
          'olas',
          '$authoring\nconst modifiers = [\n$bad\n];\n$native',
        );
        expect(
          () => generateCreatorRegistry(visuals),
          failsNaming('olas.dart', reason),
          reason: bad,
        );
      }
    });

    test('variations travel next to the modifiers, in either order', () {
      const variations = '''const variations = [
  CreatorVariation('Tormenta', {'lados': 12, 'modo': 'Rayo', 'borde': false}),
  CreatorVariation('Calma', {'zoom': .6, 'speed': .5}),
];''';
      writeNative('olas', '$authoring\n$list\n$variations\n$native');
      writeNative('lisa', '$authoring\n$variations\n$list\n$native');
      final registry = generateCreatorRegistry(visuals);
      expect(
        'variations: visual_0.variations'.allMatches(registry).length +
            'variations: visual_1.variations'.allMatches(registry).length,
        2,
      );
    });

    test('variations are literals too', () {
      for (final (bad, reason) in [
        ("CreatorVariation('A', {'lados': pick()}),", 'necesita'),
        (r"CreatorVariation('A ${1}', {'lados': 3}),", r'$'),
        ("CreatorVariation('A', <String, Object>{'lados': 3}),", 'falta'),
      ]) {
        writeNative(
          'olas',
          '$authoring\n$list\nconst variations = [\n$bad\n];\n$native',
        );
        expect(
          () => generateCreatorRegistry(visuals),
          failsNaming('olas.dart', reason),
          reason: bad,
        );
      }
      writeNative('olas', "$authoring\n$list\n$list\n$native");
      expect(
        () => generateCreatorRegistry(visuals),
        failsNaming('olas.dart', 'dos veces'),
      );
    });

    test('a variations list that would not compile is refused first', () {
      for (final (bad, reason) in [
        ('const variations = [];', 'vacía'),
        (
          'const variations = <CreatorModifier>[CreatorVariation(\'A\', {\'lados\': 4})];',
          'CreatorVariation',
        ),
        ("const variations = [CreatorVariation('A', {1: 2})];", 'claves'),
        ("const variations = [CreatorVariation('A', {'lados'})];", 'falta'),
        (
          "const variations = [CreatorVariation('A', {'lados': 4, 'lados': 5})];",
          'repetida',
        ),
        ("const variations = [CreatorVariation({'lados': 4})];", 'nombre'),
      ]) {
        writeNative('olas', '$authoring\n$list\n$bad\n$native');
        expect(
          () => generateCreatorRegistry(visuals),
          failsNaming('olas.dart', reason),
          reason: bad,
        );
      }
    });

    test('lists after nativeSource say where they go', () {
      writeNative('olas', '$authoring\n$native\n$list');
      expect(
        () => generateCreatorRegistry(visuals),
        failsNaming('olas.dart', 'antes de nativeSource'),
      );
      writeNative(
        'olas',
        "$authoring\n$list\n$native\nconst variations = [CreatorVariation('A', {'lados': 4})];",
      );
      expect(
        () => generateCreatorRegistry(visuals),
        failsNaming('olas.dart', 'antes de nativeSource'),
      );
    });

    test('legacy shader visuals have no modifiers', () {
      writeNative(
        'olas',
        "$authoring\n$list\nconst shaderSource = r'''vec4 paintVisual(vec2 uv, CreatorFrame f) { return vec4(1.0); }''';",
      );
      expect(
        () => generateCreatorRegistry(visuals),
        failsNaming('olas.dart', 'nativeSource'),
      );
    });
  });

  test('the complete copyable templates pass the same admission gate', () {
    final root = Directory.current.parent;
    File('${visuals.path}/olas.dart').writeAsStringSync(
      File('${root.path}/templates/visual_template.dart').readAsStringSync(),
    );
    File('${visuals.path}/olas_metadata.dart').writeAsStringSync(
      File(
        '${root.path}/templates/visual_template_metadata.dart',
      ).readAsStringSync(),
    );
    // The template teaches modifiers by declaring them.
    expect(
      generateCreatorRegistry(visuals),
      contains('modifiers: visual_0.modifiers'),
    );
    final source = File('${visuals.path}/olas.dart');
    source.writeAsStringSync(
      source.readAsStringSync().replaceFirst(
        RegExp(r'^const shaderSource =', multiLine: true),
        'const shaderSource =\n',
      ),
    );
    expect(() => generateCreatorRegistry(visuals), returnsNormally);
  });
}
