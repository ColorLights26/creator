import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'lluvia_colores_premium',
  name: 'Lluvia de Colores Premium',
  publication: CreatorPublication.draft,
  description:
      'Lluvia de luces de colores: partículas rojas, doradas y azules con núcleo brillante y estela que caen meciéndose, con luces de colores desenfocadas cerca. Sin fondo, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['festive', 'joyful', 'playful'],
  concepts: ['colorful lights', 'party', 'falling particles', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffff1f44, 0xffffc400, 0xff2f7bff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas simuladas con física: fluidas a 30 FPS en el móvil.
  framesPerSecond: 30,
);
