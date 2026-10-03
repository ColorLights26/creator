import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'fuegos_artificiales_transparente',
  name: 'Fuegos Artificiales Transparente',
  publication: CreatorPublication.draft,
  description:
      'Espectáculo de fuegos artificiales sincronizado con la música: peonías, sauces dorados, anillos y chispas que estallan con cada golpe sobre fondo transparente.',
  purposes: ['party', 'celebration', 'visualizer'],
  moods: ['festive', 'epic', 'joyful'],
  concepts: ['fireworks', 'sparks', 'celebration', 'show'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.0),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffffc247, 0xffff3d3d, 0xff52ff6a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Chispas en movimiento continuo: a 60 FPS el espectáculo es fluido.
  framesPerSecond: 60,
);
