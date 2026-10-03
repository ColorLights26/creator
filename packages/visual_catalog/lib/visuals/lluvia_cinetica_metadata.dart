import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'lluvia_cinetica',
  name: 'Lluvia Cinética',
  publication: CreatorPublication.draft,
  description:
      'Cientos de gotas de cobre suspendidas en 3D que suben y bajan juntas formando olas, espirales y cúpulas al ritmo de la música.',
  purposes: ['visualizer', 'relax', 'party'],
  moods: ['hypnotic', 'elegant', 'epic'],
  concepts: ['kinetic sculpture', 'droplets', '3d', 'waves'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff05070d, 0xffc8735a, 0xfff3d9b8, 0xff5a2a24],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Ondas continuas de gotas: a 60 FPS el movimiento es fluido.
  framesPerSecond: 60,
);
