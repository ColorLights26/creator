import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'cromo_liquido',
  name: 'Cromo Líquido',
  publication: CreatorPublication.draft,
  description: 'Gotas de metal fundido en violeta y rosa flotando sobre fondo oscuro.',
  purposes: ['party', 'visualizer'],
  moods: ['energetic', 'glossy'],
  concepts: ['chrome', 'liquid', 'blobs'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff03000c, 0xff8a2be2, 0xffff3ea5, 0xffffd1f3],
  controls: CreatorControls(intensity: 1, speed: .6, detail: 1, glow: 1),
);
