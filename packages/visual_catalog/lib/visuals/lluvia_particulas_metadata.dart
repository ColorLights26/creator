import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'lluvia_particulas',
  name: 'Lluvia de Partículas',
  publication: CreatorPublication.draft,
  description:
      'Capa transparente de lluvia de luz: partículas brillantes que caen como gotas con su estela, más o menos inclinadas por el viento, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['calm', 'cinematic', 'melancholic'],
  concepts: ['rain', 'falling particles', 'light', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff6f86a8, 0xffd6e4ff, 0xffffffff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas sencillas: a 30 FPS gastan poca batería.
  framesPerSecond: 30,
);
