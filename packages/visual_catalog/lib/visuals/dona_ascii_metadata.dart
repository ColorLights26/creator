import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'dona_ascii',
  name: 'Dona ASCII',
  publication: CreatorPublication.draft,
  description:
      'La famosa rosquilla 3D hecha sólo con caracteres de texto, girando en ámbar de monitor antiguo; con la música late, se acelera y cambia a esfera, cubo y octaedro.',
  purposes: ['visualizer', 'focus', 'party'],
  moods: ['retro', 'geeky', 'hypnotic'],
  concepts: ['ascii art', 'donut.c', 'terminal', '3d'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff050300, 0xffffb000, 0xffff5a00, 0xfffff2c0],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La figura gira sin parar: a 60 FPS es fluido.
  framesPerSecond: 30, // energía: ver energy/frame_rate_record.json
);
