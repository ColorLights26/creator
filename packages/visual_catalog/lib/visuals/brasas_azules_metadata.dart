import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'brasas_azules',
  name: 'Brasas Azules',
  publication: CreatorPublication.draft,
  description:
      'Capa transparente de brasas azules: chispas de fuego frío que suben desde abajo con un rastro largo y se apagan, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['cool', 'mysterious', 'cinematic'],
  concepts: ['blue embers', 'sparks', 'particles', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff0b3bff, 0xff1f9bff, 0xffc8f0ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas sencillas: a 30 FPS gastan poca batería.
  framesPerSecond: 30,
);
