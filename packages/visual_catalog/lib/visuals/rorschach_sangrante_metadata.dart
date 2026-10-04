import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'rorschach_sangrante',
  name: 'Rorschach Sangrante',
  publication: CreatorPublication.draft,
  description:
      'Una mancha de Rorschach de tinta roja como la sangre que late como un corazón y gotea hacia abajo en regueros que se alargan sin parar sobre el papel.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['disturbing', 'dark', 'intense'],
  concepts: ['rorschach', 'inkblot', 'dripping', 'blood red'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xffe8dcc4, 0xff3a0003, 0xffb8000e, 0xffff2a2a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta cambia de forma sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
