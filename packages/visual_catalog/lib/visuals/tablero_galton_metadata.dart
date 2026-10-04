import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'tablero_galton',
  name: 'Tablero de Galton',
  publication: CreatorPublication.draft,
  description:
      'Cientos de bolas de colores caen rebotando entre clavos y se apilan formando la campana perfecta del azar; cada golpe suelta una ráfaga y cuando se llena se vacía.',
  purposes: ['visualizer', 'focus', 'relax'],
  moods: ['satisfying', 'playful', 'warm'],
  concepts: ['galton board', 'plinko', 'probability', 'bell curve'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 10),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff06040a, 0xffff2a1a, 0xffff9a00, 0xffffde3a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las bolas rebotan sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
