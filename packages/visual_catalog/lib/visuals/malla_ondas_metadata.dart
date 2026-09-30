import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'malla_ondas',
  name: 'Malla de Ondas',
  publication: CreatorPublication.draft,
  description: 'Miles de puntos azules ondulando como agua vista desde arriba.',
  purposes: ['relax', 'visualizer'],
  moods: ['calm', 'fluid'],
  concepts: ['waves', 'dots', 'water'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff03071c, 0xff1f6fd0, 0xff7fe9ff, 0xffd9fbff],
  controls: CreatorControls(intensity: 1, speed: .6, detail: 1, glow: .8),
);
