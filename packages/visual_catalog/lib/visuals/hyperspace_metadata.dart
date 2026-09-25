import 'package:scene_compositor/authoring.dart';

// Datos del visual. El código se encuentra en el archivo del mismo nombre
// sin el sufijo _metadata. ID único; aparece en Studio. Color Lights exige revisión.
const metadata = CreatorVisualMetadata(
  id: 'hyperspace',
  name: 'Hiperespacio',
  publication: CreatorPublication.draft,
  description:
      'Túnel de estrellas que se acelera con los graves y estalla en cada beat.',
  purposes: ['party', 'visualizer', 'ambient'],
  moods: ['energetic', 'futuristic'],
  concepts: ['warp', 'stars', 'tunnel', 'speed'],
  credits: CreatorCredits(
    author: 'Chic Apps',
    license: 'Proprietary',
    source: 'Creator Studio collection',
  ),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff010208, 0xff4fc8ff, 0xff8f6bff, 0xfff2f8ff],
  controls: CreatorControls(intensity: 1, speed: .8, detail: 1, glow: .9),
);
