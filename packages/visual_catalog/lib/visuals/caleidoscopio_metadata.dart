import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'caleidoscopio',
  name: 'Caleidoscopio',
  publication: CreatorPublication.draft,
  description: 'Doce segmentos espejados con pétalos, anillos y destellos girando.',
  purposes: ['party', 'visualizer'],
  moods: ['hypnotic', 'colorful'],
  concepts: ['kaleidoscope', 'petals', 'symmetry'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff07020f, 0xffff2e9a, 0xff3ef0ff, 0xffffb03a],
  controls: CreatorControls(intensity: 1, speed: .7, detail: 1, glow: .9),
);
