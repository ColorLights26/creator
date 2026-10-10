import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'atractor_clifford',
  name: 'Atractor de Clifford',
  publication: CreatorPublication.draft,
  description:
      'Decenas de miles de puntos siguen una fórmula caótica y forman velos de seda naranja y dorada que se pliegan y se transforman sin parar al ritmo de la música.',
  purposes: ['visualizer', 'relax', 'focus'],
  moods: ['hypnotic', 'silky', 'warm'],
  concepts: ['clifford attractor', 'strange attractor', 'chaos', 'particles'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff050100, 0xffd8200a, 0xffff8a00, 0xffffe9a8],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Los velos cambian de forma sin parar: a 60 FPS es fluido.
  framesPerSecond: 30,
);
