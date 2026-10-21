import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_fuegos_artificiales_transparente',
  name: 'Reactiva · Fuegos Artificiales',
  publication: CreatorPublication.draft,
  description:
      'Versión reactiva: sin música no dibuja nada y sólo aparece un instante con el golpe grande (o el momento que elijas en Ajustes) y desaparece. Espectáculo de fuegos artificiales sincronizado con la música: peonías, sauces dorados, anillos y chispas que estallan con cada golpe sobre fondo transparente.',
  purposes: ['party', 'celebration', 'visualizer'],
  moods: ['festive', 'epic', 'joyful'],
  concepts: ['aparición momentánea', 'fireworks', 'sparks', 'celebration', 'show'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.2),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffffc247, 0xffff3d3d, 0xff52ff6a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Chispas en movimiento continuo: a 60 FPS el espectáculo es fluido.
  framesPerSecond: 30,
);
