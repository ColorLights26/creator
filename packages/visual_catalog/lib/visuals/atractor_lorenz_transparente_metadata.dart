import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'atractor_lorenz_transparente',
  name: 'Atractor de Lorenz Transparente',
  publication: CreatorPublication.draft,
  description:
      'Miles de partículas azul eléctrico recorren en 3D la mariposa del caos; cada golpe las dispersa y vuelven a caer sobre la forma sobre fondo transparente.',
  purposes: ['visualizer', 'focus', 'relax'],
  moods: ['hypnotic', 'scientific', 'epic'],
  concepts: ['lorenz attractor', 'chaos', 'particles', '3d'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff1e6bff, 0xff00e1ff, 0xffffffff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas en movimiento continuo: a 60 FPS el giro es fluido.
  framesPerSecond: 30,
);
