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

  test('the limit counts complete pairs rather than both files', () {
    for (var i = 0; i < 64; i++) {
      writePair('visual_$i');
    }
    expect(generateCreatorRegistry(visuals), contains('metadata_63.metadata'));
    writePair('visual_64');
    expect(() => generateCreatorRegistry(visuals), throwsFormatException);
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
    expect(() => generateCreatorRegistry(visuals), returnsNormally);
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
