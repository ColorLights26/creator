import 'package:scene_compositor/authoring.dart';

// Datos del visual. El código se encuentra en el archivo del mismo nombre
// sin el sufijo _metadata. ID único; aparece en Studio. Color Lights exige revisión.
const metadata = CreatorVisualMetadata(
  id: 'ocean_caustics',
  name: 'Océano · luz sumergida',
  publication: CreatorPublication.draft,
  description:
      'Caústicas submarinas con rayos de luz descendentes; movimiento ambiental.',
  purposes: ['relax', 'sleep', 'focus'],
  moods: ['calm', 'meditative'],
  concepts: ['ocean', 'caustics', 'underwater', 'light'],
  credits: CreatorCredits(
    author: 'Chic Apps',
    license: 'Proprietary',
    source: 'Creator Studio collection',
  ),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.none,
  colors: [0xff021018, 0xff0a5570, 0xff3fe0c8, 0xffeafff8],
  controls: CreatorControls(intensity: 1, speed: .5, detail: 1, glow: .7),
);
