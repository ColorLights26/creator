import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'ceniza',
  name: 'Ceniza',
  publication: CreatorPublication.draft,
  description:
      'Capa transparente de ceniza: motas grises que caen lentas y, entre ellas, alguna que todavía arde en naranja, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['dark', 'cinematic', 'melancholic'],
  concepts: ['ash', 'embers', 'falling particles', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff3d3a38, 0xff8e8984, 0xffff6a10],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas sencillas: a 30 FPS gastan poca batería.
  framesPerSecond: 30,
);
