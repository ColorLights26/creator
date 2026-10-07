import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'flor_vida_transparente',
  name: 'Flor de la Vida Transparente',
  publication: CreatorPublication.draft,
  description:
      'Geometría sagrada: la Flor de la Vida se dibuja círculo a círculo, sus pétalos se encienden en oro y violeta y se convierte en el cubo de Metatrón, latiendo con la música sobre fondo transparente.',
  purposes: ['visualizer', 'relax', 'focus'],
  moods: ['spiritual', 'hypnotic', 'elegant'],
  concepts: ['flower of life', 'sacred geometry', 'metatron cube', 'mandala'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 12),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff9b30ff, 0xffffb81c, 0xffff3d7f],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Los círculos se trazan de forma continua: a 60 FPS es fluido.
  framesPerSecond: 30, // energía: ver energy/frame_rate_record.json
);
