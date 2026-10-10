import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'tablero_galton_transparente',
  name: 'Tablero de Galton Transparente',
  publication: CreatorPublication.draft,
  description:
      'Cientos de bolas de colores caen rebotando entre clavos y se apilan formando la campana perfecta del azar; cada golpe suelta una ráfaga y cuando se llena se vacía sobre fondo transparente.',
  purposes: ['visualizer', 'focus', 'relax'],
  moods: ['satisfying', 'playful', 'warm'],
  concepts: ['galton board', 'plinko', 'probability', 'bell curve'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 10),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffff2a1a, 0xffff9a00, 0xffffde3a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las bolas rebotan sin parar: a 60 FPS es fluido.
  framesPerSecond: 30,
);
