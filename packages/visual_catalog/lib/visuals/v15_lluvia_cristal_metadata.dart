import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'v15_lluvia_cristal',
  name: 'Lluvia sobre Cristal',
  publication: CreatorPublication.draft,
  description: 'Gotas de lluvia con física de deslizamiento y coalescencia sobre cristal empañado, refracción de lente y bokeh nocturno de luces de ciudad.',
  purposes: ['atmosphere', 'relax', 'nature'],
  moods: ['peaceful', 'nostalgic', 'dreamy'],
  concepts: ['rain', 'glass', 'bokeh', 'droplets', 'night', 'city lights', 'refraction'],
  credits: CreatorCredits(author: 'Visuales Inmersivas', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff05060a, 0xffffb45e, 0xff5ad7ff, 0xffff4d5e],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
