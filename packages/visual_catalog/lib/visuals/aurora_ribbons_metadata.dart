import 'package:scene_compositor/authoring.dart';

// Datos del visual. El código se encuentra en el archivo del mismo nombre
// sin el sufijo _metadata. ID único; aparece en Studio. Color Lights exige revisión.
const metadata = CreatorVisualMetadata(
  id: 'aurora_ribbons',
  name: 'Aurora · cintas de luz',
  publication: CreatorPublication.draft,
  description: 'Cintas de aurora suaves que se expanden con la música.',
  purposes: ['relax', 'visualizer'],
  moods: ['calm', 'dreamy'],
  concepts: ['aurora', 'light', 'ribbons'],
  credits: CreatorCredits(
    author: 'Chic Apps',
    license: 'Proprietary',
    source: 'Visual Studio examples',
  ),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff030918, 0xff20d7ba, 0xff6562eb, 0xffffb9de],
  controls: CreatorControls(intensity: 1, speed: .6, detail: 1, glow: .8),
);
