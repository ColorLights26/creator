import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'rorschach_rayos_x',
  name: 'Rorschach Rayos X',
  publication: CreatorPublication.draft,
  description:
      'Una mancha de Rorschach vista en una placa de rayos X: dentro se ven huesos, costillas y venas, un corazón que late y un escáner que la recorre; cambia de forma con cada golpe.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['eerie', 'scientific', 'hypnotic'],
  concepts: ['rorschach', 'x-ray', 'bones', 'heartbeat'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 4),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff020409, 0xff2a78ff, 0xffff2a3a, 0xffe8f6ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta cambia de forma sin parar: a 60 FPS es fluido.
  framesPerSecond: 30, // energía: 60 no cabe; ver energy/frame_rate_record.json
);
