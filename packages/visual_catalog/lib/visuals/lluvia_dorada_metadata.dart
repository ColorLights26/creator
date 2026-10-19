import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'lluvia_dorada',
  name: 'Lluvia Dorada',
  publication: CreatorPublication.draft,
  description:
      'Capa transparente de lluvia dorada: purpurina de oro que cae despacio girando y destella cuando le da la luz, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['festive', 'glamorous', 'elegant'],
  concepts: ['glitter', 'gold', 'falling particles', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff8a5a00, 0xffffc02e, 0xfffff2c8],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas sencillas: a 30 FPS gastan poca batería.
  framesPerSecond: 30,
);
