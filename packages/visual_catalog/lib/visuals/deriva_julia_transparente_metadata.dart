import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'deriva_julia_transparente',
  name: 'Deriva de Julia Transparente',
  publication: CreatorPublication.draft,
  description: 'Conjunto de Julia iterado por píxel en la GPU sobre fondo transparente.',
  purposes: ['relax', 'visualizer'],
  moods: ['dreamy', 'hypnotic'],
  concepts: ['fractal', 'julia', 'iteration'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffff8f6b, 0xff5ad1e8, 0xfff5a524],
  controls: CreatorControls(intensity: 1, speed: .5, detail: 1, glow: .7),
);
