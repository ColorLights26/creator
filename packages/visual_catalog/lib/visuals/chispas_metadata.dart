import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'chispas',
  name: 'Chispas',
  publication: CreatorPublication.draft,
  description:
      'Capa transparente de chispas: pocas chispas finas y rápidas que saltan hacia arriba en abanico con su estela y caen en arco, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['energetic', 'intense', 'cinematic'],
  concepts: ['sparks', 'fire', 'particles', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffff5a00, 0xffffb02e, 0xfffff4d6],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas sencillas: a 30 FPS gastan poca batería.
  framesPerSecond: 30,
);
