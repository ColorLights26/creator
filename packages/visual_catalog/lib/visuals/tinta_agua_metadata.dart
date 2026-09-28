import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'tinta_agua',
  name: 'Tinta en Agua',
  publication: CreatorPublication.draft,
  description: 'Doce metaballs de tinta fundiéndose en agua, con vetas y espuma en el frente.',
  purposes: ['relax', 'visualizer'],
  moods: ['fluid', 'calm'],
  concepts: ['metaballs', 'ink', 'water'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff06141c, 0xff0d8c9e, 0xff8cf2ef, 0xff0a2c33],
  controls: CreatorControls(intensity: 1, speed: .6, detail: 1, glow: .8),
);
