import 'package:scene_compositor/authoring.dart';

// Datos del visual. El código se encuentra en el archivo del mismo nombre
// sin el sufijo _metadata. ID único; aparece en Studio. Color Lights exige revisión.
const metadata = CreatorVisualMetadata(
  id: 'neon_grid',
  name: 'Neón · horizonte retro',
  publication: CreatorPublication.draft,
  description:
      'Sol retro de neón sobre una rejilla que avanza latiendo con la música.',
  purposes: ['party', 'ambient', 'decor'],
  moods: ['energetic', 'nostalgic'],
  concepts: ['retrowave', 'grid', 'sun', 'neon'],
  credits: CreatorCredits(
    author: 'Chic Apps',
    license: 'Proprietary',
    source: 'Creator Studio collection',
  ),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff070312, 0xffff2e6e, 0xff7f3bff, 0xff29e2ff],
  controls: CreatorControls(intensity: 1, speed: .55, detail: 1, glow: .85),
);
