import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'fuego_azul',
  name: 'Fuego Azul',
  publication: CreatorPublication.draft,
  description:
      'Llamas de fuego azul hechas de partículas que suben, se retuercen y se enfrían de blanco a azul (abajo, en dos filas o por toda la pantalla), con chispas que suben. Sin fondo, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['mysterious', 'intense', 'cinematic'],
  concepts: ['blue fire', 'flames', 'sparks', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff081a8a, 0xff1f6bff, 0xffbfeaff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas simuladas con física: fluidas a 30 FPS en el móvil.
  framesPerSecond: 30,
);
