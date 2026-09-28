import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'galaxia_espiral',
  name: 'Galaxia Espiral',
  publication: CreatorPublication.draft,
  description: 'Tres brazos de estrellas orbitando un núcleo incandescente que respira con la música.',
  purposes: ['relax', 'visualizer'],
  moods: ['dreamy', 'cosmic'],
  concepts: ['galaxy', 'stars', 'space'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff03020a, 0xffffe9b8, 0xffff9ad5, 0xff7ad7ff],
  controls: CreatorControls(intensity: 1, speed: .6, detail: 1, glow: .9),
);
