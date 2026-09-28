import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'deriva_julia',
  name: 'Deriva de Julia',
  publication: CreatorPublication.draft,
  description: 'Conjunto de Julia iterado por píxel en la GPU, con paleta coseno y coloración suave.',
  purposes: ['relax', 'visualizer'],
  moods: ['dreamy', 'hypnotic'],
  concepts: ['fractal', 'julia', 'iteration'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff08050e, 0xffff8f6b, 0xff5ad1e8, 0xfff5a524],
  controls: CreatorControls(intensity: 1, speed: .5, detail: 1, glow: .7),
);
