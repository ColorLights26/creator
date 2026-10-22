import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_fuegos_artificiales_transparente',
  name: 'Reactiva Mejorada · Fuegos Artificiales',
  publication: CreatorPublication.draft,
  description:
      'Versión reactiva mejorada: sin música no dibuja nada; con música se ve tanto como suena y cada golpe la enciende más. Espectáculo de fuegos artificiales sincronizado con la música: peonías, sauces dorados, anillos y chispas que estallan con cada golpe sobre fondo transparente.',
  purposes: ['party', 'celebration', 'visualizer'],
  moods: ['festive', 'epic', 'joyful'],
  concepts: ['aparición momentánea', 'reactiva mejorada', 'fireworks', 'sparks', 'celebration', 'show'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.2),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffffc247, 0xffff3d3d, 0xff52ff6a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Chispas en movimiento continuo: a 60 FPS el espectáculo es fluido.
  framesPerSecond: 30,
);
