import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'destellos_dorados',
  name: 'Destellos Dorados',
  publication: CreatorPublication.draft,
  description:
      'Capa transparente de destellos dorados: puntos de luz que aparecen en sitios al azar, titilan como estrellas y se apagan, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['magical', 'elegant', 'festive'],
  concepts: ['sparkles', 'glitter', 'stars', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffb8860b, 0xffffc83d, 0xfffff6d8],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas sencillas: a 30 FPS gastan poca batería.
  framesPerSecond: 30,
);
