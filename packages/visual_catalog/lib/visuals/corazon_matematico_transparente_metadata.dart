import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'corazon_matematico_transparente',
  name: 'Corazón Matemático Transparente',
  publication: CreatorPublication.draft,
  description:
      'Cientos de líneas de neón rojo, magenta y violeta unen los puntos de un círculo según las tablas de multiplicar y forman corazones, flores y estrellas sobre fondo transparente.',
  purposes: ['visualizer', 'focus', 'party'],
  moods: ['hypnotic', 'elegant', 'vivid'],
  concepts: ['times tables', 'cardioid', 'string art', 'mathematics'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3.0),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffff1744, 0xffff00c8, 0xff8a2bff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las figuras se transforman sin parar: a 60 FPS el cambio es fluido.
  framesPerSecond: 30, // energía: ver energy/frame_rate_record.json
);
