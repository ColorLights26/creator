import 'package:scene_compositor/authoring.dart';

// Datos del visual. El código se encuentra en el archivo del mismo nombre
// sin el sufijo _metadata. ID único; aparece en Studio. Color Lights exige revisión.
const metadata = CreatorVisualMetadata(
  id: 'deep_space',
  name: 'Espacio · nebulosa',
  publication: CreatorPublication.draft,
  description:
      'Nebulosas profundas con estrellas titilantes y fugaces ocasionales.',
  purposes: ['relax', 'sleep', 'ambient'],
  moods: ['calm', 'dreamy', 'mysterious'],
  concepts: ['space', 'nebula', 'stars', 'galaxy'],
  credits: CreatorCredits(
    author: 'Chic Apps',
    license: 'Proprietary',
    source: 'Creator Studio collection',
  ),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff020312, 0xff1f9e8f, 0xff9b4dd9, 0xfff2f6ff],
  controls: CreatorControls(intensity: 1, speed: .45, detail: 1, glow: .8),
);
