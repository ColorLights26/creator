import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'v07_aurora_plasma',
  name: 'Aurora Boreal de Plasma',
  publication: CreatorPublication.draft,
  description: 'Cortinas de plasma ionizado con ondulación armónica multi-frecuencia, filamentos centrales y siluetas montañosas sobre noche polar.',
  purposes: ['atmosphere', 'visualizer', 'relax'],
  moods: ['dreamy', 'mystical', 'calm'],
  concepts: ['aurora borealis', 'plasma', 'solar wind', 'mountains'],
  credits: CreatorCredits(author: 'Visuales Inmersivas', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff010610, 0xff00ffa3, 0xff00e5ff, 0xff9d4edd],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
