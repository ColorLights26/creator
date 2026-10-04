import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'arbol_fractal',
  name: 'Árbol Fractal',
  publication: CreatorPublication.draft,
  description:
      'Árbol de luz que se ramifica una y otra vez del dorado al fucsia: se mece con los graves, cada golpe sube como un pulso por sus ramas y florece en las puntas.',
  purposes: ['visualizer', 'relax', 'focus'],
  moods: ['organic', 'glowing', 'calm'],
  concepts: ['fractal tree', 'recursion', 'branches', 'bloom'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff030005, 0xffffb000, 0xffff2fa8, 0xffffe9c4],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las ramas se mecen sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
