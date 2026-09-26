import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'seda_bioluminiscente',
  name: 'Seda Bioluminiscente',
  publication: CreatorPublication.draft,
  description:
      'Cintas etéreas de seda bioluminiscente en gravedad cero con ondulaciones fluidas y esporas de luz reactivas al ritmo.',
  purposes: ['visualizer', 'relax', 'meditation'],
  moods: ['ethereal', 'dreamy', 'organic'],
  concepts: ['silk', 'bioluminescent', 'aurora', 'deep_sea', 'fluid'],
  credits: CreatorCredits(
    author: 'Color Lights 26',
    license: 'Proprietary',
    source: 'Color Lights Studio',
  ),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xFF020612, 0xFF14F59A, 0xFF38E1FF, 0xFF9E00FF],
  controls: CreatorControls(intensity: 1.0, speed: 1.0, detail: 1.0, glow: 1.1),
);
