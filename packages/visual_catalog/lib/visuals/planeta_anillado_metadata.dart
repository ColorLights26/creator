import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'planeta_anillado',
  name: 'Planeta Anillado',
  publication: CreatorPublication.draft,
  description:
      'Gigante gaseoso cuyos anillos se encienden como un ecualizador; los golpes lanzan ondas por los anillos y auroras en los polos.',
  purposes: ['relax', 'visualizer', 'party'],
  moods: ['cosmic', 'epic', 'elegant'],
  concepts: ['planet', 'rings', 'space', 'spectrum'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff020309, 0xffc8613a, 0xff5aa8ff, 0xfff3d9a4],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
