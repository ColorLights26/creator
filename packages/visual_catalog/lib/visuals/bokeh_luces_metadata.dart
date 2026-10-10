import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'bokeh_luces',
  name: 'Bokeh',
  publication: CreatorPublication.draft,
  description:
      'Luces desenfocadas ámbar, rosa y azul que flotan a distintas profundidades y laten suavemente con la música.',
  purposes: ['relax', 'visualizer', 'focus'],
  moods: ['dreamy', 'elegant', 'calm'],
  concepts: ['bokeh', 'lights', 'depth of field', 'glow'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff07060d, 0xffffb15c, 0xffff7aa8, 0xff6fa8ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las luces flotan sin parar: a 60 FPS la deriva es suave.
  framesPerSecond: 30,
);
