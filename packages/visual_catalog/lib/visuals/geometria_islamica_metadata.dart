import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'geometria_islamica',
  name: 'Geometría Islámica',
  publication: CreatorPublication.draft,
  description:
      'Lacería de estrellas de 8 y 12 puntas como en los azulejos de la Alhambra: cintas de oro sobre carmín, esmeralda y azul noche que se transforman y brillan con la música.',
  purposes: ['visualizer', 'focus', 'relax'],
  moods: ['elegant', 'hypnotic', 'ornamental'],
  concepts: ['islamic geometry', 'girih', 'star pattern', 'zellige'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff050b2a, 0xffffc23a, 0xffe0102f, 0xff00a86b],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las estrellas se transforman sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
