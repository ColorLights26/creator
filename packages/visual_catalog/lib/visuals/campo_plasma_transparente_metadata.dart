import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'campo_plasma_transparente',
  name: 'Campo de Plasma Transparente',
  publication: CreatorPublication.draft,
  description: 'Niebla de color turquesa, lima y rosa en movimiento sobre fondo transparente.',
  purposes: ['relax', 'visualizer'],
  moods: ['dreamy', 'fluid'],
  concepts: ['plasma', 'fog', 'gradient'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff00c2b2, 0xffffd93d, 0xffff2fb9],
  controls: CreatorControls(intensity: 1, speed: .6, detail: 1, glow: .7),
);
