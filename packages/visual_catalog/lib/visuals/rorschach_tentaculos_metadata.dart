import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'rorschach_tentaculos',
  name: 'Rorschach Tentáculos',
  publication: CreatorPublication.draft,
  description:
      'Una mancha de Rorschach de la que brotan tentáculos de tinta que se retuercen, se enroscan y se lanzan hacia fuera con cada golpe, en la penumbra de una lámina vieja.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['disturbing', 'dark', 'organic'],
  concepts: ['rorschach', 'tentacles', 'creature', 'ink'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 4),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xffd9d2b6, 0xff070404, 0xff6a000e, 0xffd4142a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta cambia de forma sin parar: a 60 FPS es fluido.
  framesPerSecond: 30, // energía: ver energy/frame_rate_record.json
);
