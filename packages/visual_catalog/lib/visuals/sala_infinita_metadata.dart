import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'sala_infinita',
  name: 'Sala Infinita',
  publication: CreatorPublication.draft,
  description:
      'Una sala de espejos como las de Yayoi Kusama: cientos de luces colgantes reflejadas hasta el infinito que cambian de color en olas con la música mientras flotas entre ellas.',
  purposes: ['visualizer', 'relax', 'party'],
  moods: ['immersive', 'dreamy', 'vivid'],
  concepts: ['infinity mirror room', 'kusama', 'lights', 'reflections'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff020104, 0xffff1e3c, 0xffff8c00, 0xffffd93a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Se avanza entre las luces sin parar: a 60 FPS es fluido.
  framesPerSecond: 30, // energía: ver energy/frame_rate_record.json
);
