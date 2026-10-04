import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'rorschach_tentaculos',
  name: 'Rorschach Tentáculos',
  publication: CreatorPublication.draft,
  description:
      'Una mancha de Rorschach de la que brotan tentáculos de tinta que se retuercen, se enroscan y se lanzan hacia fuera con cada golpe de la música.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['disturbing', 'organic', 'dark'],
  concepts: ['rorschach', 'tentacles', 'ink', 'creature'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xffe2dcc2, 0xff080505, 0xff7a0010, 0xffd4142a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta cambia de forma sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
