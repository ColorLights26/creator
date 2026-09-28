import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'malla_topografica',
  name: 'Malla Topográfica',
  publication: CreatorPublication.draft,
  description: 'Terreno en perspectiva con rejilla proyectada, sol en el horizonte y scroll continuo.',
  purposes: ['relax', 'visualizer'],
  moods: ['calm', 'retro'],
  concepts: ['terrain', 'grid', 'perspective'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff070a10, 0xffc6e84f, 0xff78c878, 0xffeaffb0],
  controls: CreatorControls(intensity: 1, speed: .6, detail: 1, glow: .7),
);
