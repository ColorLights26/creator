import 'package:scene_compositor/authoring.dart';

// Datos del visual. El código se encuentra en el archivo del mismo nombre
// sin el sufijo _metadata. ID único; aparece en Studio. Color Lights exige revisión.
const metadata = CreatorVisualMetadata(
  id: 'aurora_ribbons',
  name: 'Aurora · cintas de luz',
  publication: CreatorPublication.draft,
  description:
      'Cortinas de aurora cinematográficas con rayos finos sobre cielo estrellado.',
  purposes: ['relax', 'visualizer', 'ambient'],
  moods: ['calm', 'dreamy'],
  concepts: ['aurora', 'light', 'ribbons', 'night'],
  credits: CreatorCredits(
    author: 'Chic Apps',
    license: 'Proprietary',
    source: 'Visual Studio examples',
  ),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff01030c, 0xff0a5c46, 0xff2ee6a8, 0xff9d7bff],
  controls: CreatorControls(intensity: 1, speed: .6, detail: 1, glow: .8),
);
