import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'v01_agujero_negro',
  name: 'Agujero Negro & Acreción',
  publication: CreatorPublication.draft,
  description: 'Horizonte de sucesos relativista, disco de acreción con corrimiento Doppler, chorros polares y lente gravitacional de Einstein.',
  purposes: ['cosmic', 'visualizer', 'relax'],
  moods: ['epic', 'hypnotic', 'deep'],
  concepts: ['black hole', 'accretion disk', 'relativity', 'space'],
  credits: CreatorCredits(author: 'Visuales Inmersivas', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff0d061a, 0xffff9100, 0xff00e5ff, 0xffd500f9],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
