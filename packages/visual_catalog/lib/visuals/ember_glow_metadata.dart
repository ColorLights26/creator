import 'package:scene_compositor/authoring.dart';

// Datos del visual. El código se encuentra en el archivo del mismo nombre
// sin el sufijo _metadata. ID único; aparece en Studio. Color Lights exige revisión.
const metadata = CreatorVisualMetadata(
  id: 'ember_glow',
  name: 'Fuego · ascuas vivas',
  publication: CreatorPublication.draft,
  description:
      'Hogar de brasas con llamas suaves y chispas que suben con la música.',
  purposes: ['relax', 'ambient', 'decor'],
  moods: ['warm', 'cozy'],
  concepts: ['fire', 'embers', 'glow', 'hearth'],
  credits: CreatorCredits(
    author: 'Chic Apps',
    license: 'Proprietary',
    source: 'Creator Studio collection',
  ),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff0b0402, 0xff9a1e00, 0xffff7a1a, 0xffffd98a],
  controls: CreatorControls(intensity: 1, speed: .6, detail: 1, glow: .9),
);
