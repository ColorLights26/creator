import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'laberinto_vivo',
  name: 'Laberinto Vivo',
  publication: CreatorPublication.draft,
  description:
      'Un laberinto que se excava solo, se inunda de luz de colores desde la entrada y al final muestra en blanco el camino hasta la salida; cada golpe acelera la búsqueda.',
  purposes: ['visualizer', 'focus', 'relax'],
  moods: ['satisfying', 'digital', 'hypnotic'],
  concepts: ['maze generation', 'pathfinding', 'algorithm', 'neon'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 9),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff040306, 0xffff1f3d, 0xffff8a00, 0xffffe14a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // El excavado avanza celda a celda: a 60 FPS es fluido.
  framesPerSecond: 30,
);
