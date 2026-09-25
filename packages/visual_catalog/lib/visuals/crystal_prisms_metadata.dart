import 'package:scene_compositor/authoring.dart';

// Datos del visual. El código se encuentra en el archivo del mismo nombre
// sin el sufijo _metadata. ID único; aparece en Studio. Color Lights exige revisión.
const metadata = CreatorVisualMetadata(
  id: 'crystal_prisms',
  name: 'Prismas de cristal',
  publication: CreatorPublication.draft,
  description:
      'Cristales flotantes con dispersión cromática en los bordes; capa sutil.',
  purposes: ['ambient', 'decor', 'relax'],
  moods: ['elegant', 'dreamy'],
  concepts: ['crystal', 'prism', 'glass', 'overlay'],
  credits: CreatorCredits(
    author: 'Chic Apps',
    license: 'Proprietary',
    source: 'Creator Studio collection',
  ),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0xff0d0a1a, 0xff7fe0ff, 0xffb48cff, 0xfff0f4ff],
  controls: CreatorControls(intensity: 1, speed: .5, detail: 1, glow: .85),
);
