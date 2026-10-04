import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'laberinto_truchet',
  name: 'Laberinto Truchet',
  publication: CreatorPublication.draft,
  description:
      'Losetas con arcos de neón lima y rojo que forman caminos sin fin; cada golpe gira una ola de losetas y la luz corre por los caminos nuevos.',
  purposes: ['visualizer', 'focus', 'party'],
  moods: ['hypnotic', 'graphic', 'electric'],
  concepts: ['truchet tiles', 'maze', 'generative', 'neon'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff020402, 0xffa8ff00, 0xffff1a3c, 0xffffffff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las losetas giran y la luz corre sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
