import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/studio/visual_collections.dart';
import '../lib/studio/visual_uploads.dart';
import '../tool/generate_visual_collections.dart';

void main() {
  late Directory temporary;
  late Directory repo;
  final generator = File('tool/generate_visual_collections.dart').absolute;
  final dartExecutable =
      (Process.runSync('which', ['dart']).stdout as String).trim();

  ProcessResult git(Directory root, List<String> arguments, {String? date}) {
    final result = Process.runSync(
      'git',
      ['-C', root.path, ...arguments],
      environment: {
        if (date != null) 'GIT_AUTHOR_DATE': date,
        if (date != null) 'GIT_COMMITTER_DATE': date,
      },
    );
    if (result.exitCode != 0) {
      throw StateError('git ${arguments.join(' ')}: ${result.stderr}');
    }
    return result;
  }

  void pair(Directory root, String filename, {String? id}) {
    final folder = Directory('${root.path}/packages/visual_catalog/lib/visuals')
      ..createSync(recursive: true);
    File('${folder.path}/$filename.dart').writeAsStringSync(
      "const shaderSource = r'''vec4 paintVisual() { return vec4(1.0); }''';",
    );
    File('${folder.path}/${filename}_metadata.dart').writeAsStringSync(
      "import 'package:scene_compositor/authoring.dart';\n"
      'const metadata = CreatorVisualMetadata(\n'
      '  description: "id: \'not_the_id\'",\n'
      "  id: '${id ?? filename}', name: '$filename',\n"
      ');\n',
    );
  }

  void commit(Directory root, String date) {
    git(root, ['add', 'packages']);
    git(root, [
      '-c',
      'user.name=Franco david',
      '-c',
      'user.email=franco@example.test',
      'commit',
      '-qm',
      'Entrega de visuales',
    ], date: date);
  }

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('creator-deliveries-');
    repo = Directory('${temporary.path}/creator')..createSync();
    git(repo, ['init', '-q']);
  });
  tearDown(() => temporary.deleteSync(recursive: true));

  test(
    'a new delivery creates its dated batch without editing collections',
    () {
      pair(repo, 'first');
      commit(repo, '2026-10-21T23:30:00-05:00');
      writeStudioVisualUploads(repo);
      pair(repo, 'second');
      commit(repo, '2026-10-22T01:00:00-05:00');
      final uploads = writeStudioVisualUploads(repo);
      final groups = buildStudioVisualCollections(uploads);
      expect(groups.first.label, 'Nuevos de Franco david · 22 oct 2026');
      expect(groups.first.visualIds, {'second'});
      expect(groups[1].label, 'Nuevos de Franco david · 21 oct 2026');
      expect(groups[1].visualIds, {'first'});
      // UTC would move the late-night upload to the wrong day.
      expect(uploads.first.date, '2026-10-21');
      final before =
          File('${repo.path}/$studioUploadsAsset').readAsStringSync();
      writeStudioVisualUploads(repo);
      expect(
        File('${repo.path}/$studioUploadsAsset').readAsStringSync(),
        before,
      );
    },
  );

  test('a real pull refreshes provenance automatically through the hook', () {
    pair(repo, 'first');
    commit(repo, '2026-10-21T12:00:00-05:00');
    writeStudioVisualUploads(
      repo,
      installHooks: true,
      generatorScript: generator,
      dartExecutable: dartExecutable,
    );
    final incoming = Directory('${temporary.path}/incoming');
    git(temporary, ['clone', '-q', repo.path, incoming.path]);
    pair(incoming, 'second');
    commit(incoming, '2026-10-22T12:00:00-05:00');
    git(repo, ['pull', '--ff-only', incoming.path, 'HEAD']);
    final uploads = decodeStudioVisualUploads(
      File('${repo.path}/$studioUploadsAsset').readAsStringSync(),
    );
    expect(uploads.map((item) => item.visualId), ['first', 'second']);
    expect(buildStudioVisualCollections(uploads).first.visualIds, {'second'});
  });

  test(
    'editing or renaming a stable visual does not create a new delivery',
    () {
      pair(repo, 'first');
      commit(repo, '2026-10-21T12:00:00-05:00');
      writeStudioVisualUploads(repo);
      final path = 'packages/visual_catalog/lib/visuals';
      git(repo, ['mv', '$path/first.dart', '$path/renamed.dart']);
      git(repo, [
        'mv',
        '$path/first_metadata.dart',
        '$path/renamed_metadata.dart',
      ]);
      commit(repo, '2026-10-22T12:00:00-05:00');
      final uploads = writeStudioVisualUploads(repo);
      expect(uploads.single.visualId, 'first');
      expect(uploads.single.date, '2026-10-21');
    },
  );

  test(
    'an export preserves batches without Git and shows new pairs honestly',
    () {
      pair(repo, 'first');
      commit(repo, '2026-10-21T12:00:00-05:00');
      writeStudioVisualUploads(repo);
      Directory('${repo.path}/.git').renameSync('${temporary.path}/saved-git');
      pair(repo, 'new_draft');
      final uploads = writeStudioVisualUploads(repo);
      expect(uploads.first.date, '2026-10-21');
      expect(uploads.last.date, isNull);
      final pending = buildStudioVisualCollections(
        uploads,
      ).singleWhere((item) => item.id == 'uploads_in_preparation');
      expect(pending.label, 'En preparación');
      expect(pending.visualIds, {'new_draft'});
    },
  );

  test(
    'a shallow history cannot replace known dates with its boundary date',
    () {
      pair(repo, 'first');
      commit(repo, '2026-10-21T12:00:00-05:00');
      writeStudioVisualUploads(repo);
      File(
        '${repo.path}/.git/shallow',
      ).writeAsStringSync((git(repo, ['rev-parse', 'HEAD']).stdout as String));
      pair(repo, 'new_draft');
      final uploads = writeStudioVisualUploads(repo);
      expect(uploads.first.date, '2026-10-21');
      expect(uploads.last.date, isNull);
    },
  );

  test('an invalid pair leaves the previous portable snapshot intact', () {
    pair(repo, 'first');
    commit(repo, '2026-10-21T12:00:00-05:00');
    writeStudioVisualUploads(repo);
    final snapshot = File('${repo.path}/$studioUploadsAsset');
    final before = snapshot.readAsStringSync();
    pair(repo, 'broken');
    File(
      '${repo.path}/packages/visual_catalog/lib/visuals/broken.dart',
    ).deleteSync();
    expect(() => writeStudioVisualUploads(repo), throwsFormatException);
    expect(snapshot.readAsStringSync(), before);
  });

  test(
    'reactive originals and improved copies have separate automatic filters',
    () {
      final groups = buildStudioVisualCollections(const [
        StudioVisualUpload(
          visualId: 'reactiva_beat',
          author: 'Franco',
          date: '2026-10-23',
        ),
        StudioVisualUpload(
          visualId: 'reactiva_mejorada_beat',
          author: 'Franco',
          date: '2026-10-23',
        ),
        StudioVisualUpload(
          visualId: 'particles',
          author: 'Franco',
          date: '2026-10-23',
        ),
      ]);
      expect(groups.first.visualIds, {
        'reactiva_beat',
        'reactiva_mejorada_beat',
        'particles',
      });
      expect(
        groups
            .singleWhere(
              (group) => group.label.startsWith('Reactivas mejoradas ·'),
            )
            .visualIds,
        {'reactiva_mejorada_beat'},
      );
      expect(
        groups
            .singleWhere((group) => group.label.startsWith('Reactivas ·'))
            .visualIds,
        {'reactiva_beat'},
      );
    },
  );

  test('existing repository hooks are preserved', () {
    final hook = File('${repo.path}/.git/hooks/post-merge');
    const existing = '#!/bin/sh\n# Existing team hook\n';
    hook.writeAsStringSync(existing);
    installStudioUploadHooks(repo, generator);
    expect(hook.readAsStringSync(), existing);
  });

  test('duplicate IDs and invalid dates are rejected at load time', () {
    expect(
      () => decodeStudioVisualUploads(
        '{"schemaVersion":1,"visuals":[{"id":"one"},{"id":"one"}]}',
      ),
      throwsFormatException,
    );
    expect(
      () => decodeStudioVisualUploads(
        '{"schemaVersion":1,"visuals":['
        '{"id":"one","author":"Franco","date":"2026-02-30"}]}',
      ),
      throwsFormatException,
    );
  });
}
