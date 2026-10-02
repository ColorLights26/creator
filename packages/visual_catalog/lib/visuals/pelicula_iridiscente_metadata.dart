import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'pelicula_iridiscente',
  name: 'Película Iridiscente',
  publication: CreatorPublication.draft,
  description:
      'Macro de una película de jabón con colores de interferencia que fluyen, se agitan con los graves y estallan en anillos con cada golpe.',
  purposes: ['relax', 'visualizer', 'party'],
  moods: ['dreamy', 'fluid', 'elegant'],
  concepts: ['soap film', 'iridescence', 'interference', 'bubble'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff020205, 0xffff4fb3, 0xff4fd8ff, 0xfff4f1ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
