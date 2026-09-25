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
  colors: [0xff01020a, 0xff0f7f74, 0xff8f56e0, 0xffeef4ff],
  controls: CreatorControls(intensity: 1, speed: .45, detail: 1, glow: .8),
);
