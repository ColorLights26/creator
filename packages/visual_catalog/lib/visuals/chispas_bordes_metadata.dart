import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'chispas_bordes',
  name: 'Chispas desde los Bordes',
  publication: CreatorPublication.draft,
  description:
      'Capa transparente de chispas que salen de los bordes de la pantalla hacia dentro, se frenan y se apagan dejando libre el centro, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['energetic', 'intense', 'dynamic'],
  concepts: ['sparks', 'frame', 'particles', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffd4145a, 0xffff5e3a, 0xffffd6b3],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas sencillas: a 30 FPS gastan poca batería.
  framesPerSecond: 30,
);
