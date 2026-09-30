import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'horizonte_sucesos',
  name: 'Horizonte de Sucesos',
  publication: CreatorPublication.draft,
  description: 'Agujero negro con disco de acreción diferencial, anillo fotónico, arco de Einstein y estrellas desviadas.',
  purposes: ['relax', 'visualizer'],
  moods: ['cosmic', 'dramatic'],
  concepts: ['black hole', 'accretion', 'lensing'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff030308, 0xffffd166, 0xffc9432a, 0xffdce8ff],
  controls: CreatorControls(intensity: 1, speed: .6, detail: 1, glow: .9),
);
