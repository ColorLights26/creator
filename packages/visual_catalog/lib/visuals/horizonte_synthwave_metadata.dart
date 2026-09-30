import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'horizonte_synthwave',
  name: 'Horizonte Synthwave',
  publication: CreatorPublication.draft,
  description: 'Sol retro con rejilla infinita y montañas de neón estilo años 80.',
  purposes: ['party', 'visualizer'],
  moods: ['retro', 'energetic'],
  concepts: ['synthwave', 'sun', 'grid'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff160034, 0xffff2e9a, 0xfffff36b, 0xff00fff6],
  controls: CreatorControls(intensity: 1, speed: .7, detail: 1, glow: .9),
);
