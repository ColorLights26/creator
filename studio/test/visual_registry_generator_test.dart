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

  test(
    'adding a source file automatically updates the deterministic registry',
    () {
      File(
        '${visuals.path}/zeta.dart',
      ).writeAsStringSync('const visual = null;');
      File(
        '${visuals.path}/alpha.dart',
      ).writeAsStringSync('const visual = null;');
      writeCreatorRegistry(catalog);
      final registry = File('${catalog.path}/lib/src/registry.g.dart');
      final first = registry.readAsStringSync();
      expect(first.indexOf('alpha.dart'), lessThan(first.indexOf('zeta.dart')));
      expect(first, contains('const creatorSourceVisuals'));
      expect(first, contains('visual_1.visual'));

      File(
        '${visuals.path}/middle.dart',
      ).writeAsStringSync('const visual = null;');
      writeCreatorRegistry(catalog);
      final next = registry.readAsStringSync();
      expect(next, contains("import '../visuals/middle.dart' as visual_1;"));
      expect(next, contains("import '../visuals/zeta.dart' as visual_2;"));
      expect(next, contains('visual_2.visual'));
      writeCreatorRegistry(catalog);
      expect(registry.readAsStringSync(), next);
    },
  );

  test('templates outside the visuals directory are not registered', () {
    File(
      '${catalog.path}/lib/visual_template.dart',
    ).writeAsStringSync('template');
    File(
      '${visuals.path}/aurora.dart',
    ).writeAsStringSync('const visual = null;');
    expect(
      generateCreatorRegistry(visuals),
      isNot(contains('visual_template')),
    );
  });

  test('a symlink cannot silently import source outside the catalog', () {
    final source = File('${catalog.path}/external.dart')
      ..writeAsStringSync('source');
    Link('${visuals.path}/external.dart').createSync(source.path);
    expect(() => generateCreatorRegistry(visuals), throwsFormatException);
  });
}
