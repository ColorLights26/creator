import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'llamarada',
  name: 'Llamarada',
  publication: CreatorPublication.draft,
  description:
      'Fuego vivo que ruge con los graves, lanza llamaradas y lluvias de chispas con cada golpe y multiplica las brasas con los agudos.',
  purposes: ['party', 'relax', 'visualizer'],
  moods: ['warm', 'energetic', 'cozy'],
  concepts: ['fire', 'flames', 'embers', 'sparks'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff050203, 0xffb3170c, 0xffff6a1a, 0xffffc84d],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
