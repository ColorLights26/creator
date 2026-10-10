import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'monstruo_maicena',
  name: 'Monstruo de Maicena',
  publication: CreatorPublication.draft,
  description:
      'Un fluido no newtoniano sobre un altavoz: con cada golpe de graves le brotan dedos, garras o bulbos que se retuercen y se derrumban, brillantes y húmedos.',
  purposes: ['visualizer', 'party'],
  moods: ['weird', 'organic', 'intense'],
  concepts: ['non-newtonian fluid', 'oobleck', 'speaker', 'cornstarch'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 6),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff050608, 0xff2f5a00, 0xffa6ff00, 0xfff4ffd8],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Los dedos brotan de golpe: a 60 FPS es fluido.
  framesPerSecond: 30,
);
