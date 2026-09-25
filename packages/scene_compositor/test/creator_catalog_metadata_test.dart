import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:scene_compositor/authoring.dart';

const _first = CreatorVisualDefinition(
  id: 'aurora',
  name: 'Aurora',
  shaderSource:
      'vec4 paintVisual(vec2 uv, CreatorFrame f) { return vec4(1.0); }',
  description: 'Soft light ribbons.',
  purposes: ['relax', 'visualizer'],
  moods: ['calm'],
  concepts: ['aurora'],
  credits: CreatorCredits(author: 'Artist', license: 'CC0', source: 'Original'),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3.5),
);
const _second = CreatorVisualDefinition(
  id: 'halo',
  name: 'Halo',
  shaderSource:
      'vec4 paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.5); }',
  role: CreatorRole.overlay,
  publication: CreatorPublication.published,
);

String _metadata(List<CreatorVisualDefinition> visuals) => jsonEncode({
  'schemaVersion': 1,
  'visuals': [for (final visual in visuals) visual.toMetadata()],
});

void main() {
  test(
    'separate metadata and shader preserve the existing runtime contract',
    () {
      const metadata = CreatorVisualMetadata(
        id: 'aurora',
        name: 'Aurora',
        description: 'Soft light ribbons.',
        purposes: ['relax', 'visualizer'],
        moods: ['calm'],
        concepts: ['aurora'],
        credits: CreatorCredits(
          author: 'Artist',
          license: 'CC0',
          source: 'Original',
        ),
        thumbnail: CreatorThumbnailSpec(timeSeconds: 3.5),
      );
      final joined = metadata.withShader(_first.shaderSource);
      expect(joined.toManifest(), _first.toManifest());
      expect(joined.toMetadata(), _first.toMetadata());
      expect(
        () => validateCreatorCatalog([joined, joined]),
        throwsFormatException,
      );
      expect(
        () => validateCreatorCatalog([metadata.withShader('invalid')]),
        throwsFormatException,
      );
    },
  );

  test('editorial metadata never enters the strict native manifest', () {
    expect(_first.publication, CreatorPublication.draft);
    expect(_first.toManifest().keys.toSet(), {
      'id',
      'name',
      'programId',
      'role',
      'reactivity',
      'framesPerSecond',
      'seed',
      'colors',
      'controls',
      'shaderSource',
    });
    expect(_first.toMetadata()['credits'], {
      'author': 'Artist',
      'license': 'CC0',
      'source': 'Original',
    });
    expect(_first.toMetadata()['description'], 'Soft light ribbons.');
    expect(_first.toMetadata()['thumbnail'], {'timeSeconds': 3.5});
  });

  test('generated assets merge by ID rather than metadata order', () {
    final restored = decodeCreatorCatalog(
      runtimeJson: encodeCreatorCatalog([_first, _second]),
      metadataJson: _metadata([_second, _first]),
    );
    expect(restored.map((visual) => visual.id), ['aurora', 'halo']);
    expect(restored.first.toManifest(), _first.toManifest());
    expect(restored.first.toMetadata(), _first.toMetadata());
    expect(restored.last.publication, CreatorPublication.published);
    expect(restored.last.role, CreatorRole.overlay);
    expect(() => restored.first.moods.add('other'), throwsUnsupportedError);
  });

  test('partial or contradictory generated assets fail closed', () {
    expect(
      () => decodeCreatorCatalog(
        runtimeJson: encodeCreatorCatalog([_first, _second]),
        metadataJson: _metadata([_first]),
      ),
      throwsFormatException,
    );
    expect(
      () => decodeCreatorCatalog(
        runtimeJson: encodeCreatorCatalog([_first, _second]),
        metadataJson: _metadata([_first, _first]),
      ),
      throwsFormatException,
    );
    for (final edit
        in <String, Object>{
          'role': 'overlay',
          'publication': 'anything',
        }.entries) {
      final metadata = _first.toMetadata()..[edit.key] = edit.value;
      expect(
        () => decodeCreatorCatalog(
          runtimeJson: encodeCreatorCatalog([_first]),
          metadataJson: jsonEncode({
            'schemaVersion': 1,
            'visuals': [metadata],
          }),
        ),
        throwsFormatException,
      );
    }
  });

  test('invalid metadata cannot bypass authoring admission', () {
    for (final invalid in [
      const CreatorVisualDefinition(
        id: 'bad',
        name: 'Bad',
        shaderSource: 'paintVisual',
        moods: ['Calm', 'calm'],
      ),
      const CreatorVisualDefinition(
        id: 'bad',
        name: 'Bad',
        shaderSource: 'paintVisual',
        thumbnail: CreatorThumbnailSpec(timeSeconds: -1),
      ),
      const CreatorVisualDefinition(
        id: 'bad',
        name: 'Bad',
        shaderSource: 'paintVisual',
        thumbnail: CreatorThumbnailSpec(
          assetPath: 'assets/thumbnails/../../secret.png',
        ),
      ),
    ]) {
      expect(() => validateCreatorCatalog([invalid]), throwsFormatException);
    }
  });
}
