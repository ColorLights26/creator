import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'estrellas_fugaces',
  name: 'Estrellas Fugaces',
  publication: CreatorPublication.draft,
  description:
      'Capa transparente de estrellas fugaces: de vez en cuando cruza una luz rápida en diagonal con su estela, y con cada golpe sale otra, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['magical', 'calm', 'dreamy'],
  concepts: ['shooting stars', 'meteors', 'streaks', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff8fb2ff, 0xffe4ecff, 0xffffffff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas sencillas: a 30 FPS gastan poca batería.
  framesPerSecond: 30,
);
