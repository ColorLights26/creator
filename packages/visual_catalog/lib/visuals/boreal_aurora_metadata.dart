import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'boreal_aurora',
  name: 'Aurora Boreal',
  publication: CreatorPublication.draft,
  description: 'Cintas de luz verde, azul y violeta sobre un cielo estrellado con montañas en sombra.',
  purposes: ['relax', 'visualizer'],
  moods: ['calm', 'dreamy'],
  concepts: ['aurora', 'night sky', 'stars'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff01030f, 0xff38ffc4, 0xff9d6bff, 0xffff5fd2],
  controls: CreatorControls(intensity: 1, speed: .7, detail: 1, glow: .9),
);
