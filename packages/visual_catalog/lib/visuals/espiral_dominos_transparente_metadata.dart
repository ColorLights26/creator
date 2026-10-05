import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'espiral_dominos_transparente',
  name: 'Espiral de Dominós Transparente',
  publication: CreatorPublication.draft,
  description:
      'Cientos de fichas de colores vistas desde arriba que caen en cadena formando espirales y anillos de arcoíris; la música acelera la ola y al final todas vuelven a levantarse sobre fondo transparente.',
  purposes: ['visualizer', 'relax', 'focus'],
  moods: ['satisfying', 'playful', 'vivid'],
  concepts: ['dominoes', 'chain reaction', 'spiral', 'toppling'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 7),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffff1f3d, 0xffff9100, 0xffffe14a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La ola de fichas avanza de forma continua: a 60 FPS es fluido.
  framesPerSecond: 60,
);
