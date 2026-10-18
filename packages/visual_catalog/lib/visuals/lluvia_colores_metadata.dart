import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'lluvia_colores',
  name: 'Lluvia de Colores',
  publication: CreatorPublication.draft,
  description:
      'Capa transparente de lluvia de colores: puntos de luz rojos, amarillos, naranjas y azules que caen meciéndose, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['festive', 'playful', 'joyful'],
  concepts: ['colorful particles', 'party', 'falling particles', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffff1f44, 0xffffc400, 0xff2f7bff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas sencillas: a 30 FPS gastan poca batería.
  framesPerSecond: 30,
);
