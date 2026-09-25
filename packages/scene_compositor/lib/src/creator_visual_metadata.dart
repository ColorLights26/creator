import 'creator_visual_definition.dart';

/// Author-edited metadata, independent of the file containing the shader.
/// The generated catalog joins a matching filename pair before validation.
class CreatorVisualMetadata {
  const CreatorVisualMetadata({
    required this.id,
    required this.name,
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

  CreatorVisualDefinition withShader(String shaderSource) =>
      CreatorVisualDefinition(
        shaderSource: shaderSource,
        id: id,
        name: name,
        description: description,
        purposes: purposes,
        moods: moods,
        concepts: concepts,
        credits: credits,
        thumbnail: thumbnail,
        publication: publication,
        role: role,
        reactivity: reactivity,
        framesPerSecond: framesPerSecond,
        seed: seed,
        colors: colors,
        controls: controls,
      );
}
