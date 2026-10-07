import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'rorschach_demonio',
  name: 'Rorschach Demonio',
  publication: CreatorPublication.draft,
  description:
      'Una mancha de Rorschach que arde por dentro: grietas de lava recorren la costra negra, a veces se abren dos rendijas de brasa que te miran y desaparecen; con cada golpe la lava estalla y cambia de forma.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['dark', 'mysterious', 'intense'],
  concepts: ['rorschach', 'lava', 'embers', 'demon'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 4),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff0b0706, 0xff160a08, 0xffff3a0a, 0xffffc34a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta cambia de forma sin parar: a 60 FPS es fluido.
  framesPerSecond: 30, // energía: 60 no cabe; ver energy/frame_rate_record.json
);
