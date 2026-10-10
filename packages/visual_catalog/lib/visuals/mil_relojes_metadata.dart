import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'mil_relojes',
  name: 'Mil Relojes',
  publication: CreatorPublication.draft,
  description:
      'Una pared de relojes cuyas agujas de luz se mueven juntas y dibujan olas, espirales, remolinos y rombos gigantes; cada golpe de la música las sacude con una onda.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['hypnotic', 'elegant', 'mesmerizing'],
  concepts: ['kinetic art', 'clocks', 'a million times', 'choreography'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 8),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff0b0503, 0xffd4141c, 0xffff7a00, 0xffffe2b0],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las agujas barren rápido: a 60 FPS es fluido.
  framesPerSecond: 30,
);
