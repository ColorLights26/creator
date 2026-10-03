import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'llamarada_transparente',
  name: 'Llamarada Transparente',
  publication: CreatorPublication.draft,
  description:
      'Fuego vivo que ruge con los graves, lanza llamaradas y lluvias de chispas con cada golpe y multiplica las brasas con los agudos sobre fondo transparente.',
  purposes: ['party', 'relax', 'visualizer'],
  moods: ['warm', 'energetic', 'cozy'],
  concepts: ['fire', 'flames', 'embers', 'sparks'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffb3170c, 0xffff6a1a, 0xffffc84d],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
