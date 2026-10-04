import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'arena_colores',
  name: 'Arena de Colores',
  publication: CreatorPublication.draft,
  description:
      'Simulación de arena real: chorros de arena roja, naranja, turquesa, amarilla y fucsia caen y se apilan en dunas por capas; cada golpe cambia el color y cuando se llena se vacía por el centro.',
  purposes: ['visualizer', 'relax', 'focus'],
  moods: ['satisfying', 'playful', 'vivid'],
  concepts: ['falling sand', 'sand art', 'cellular automaton', 'layers'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 12),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff07050a, 0xffff1744, 0xffffa000, 0xff00e5c0],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Cada grano cae paso a paso: a 60 FPS es fluido.
  framesPerSecond: 60,
);
