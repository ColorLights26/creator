import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'chispas_bordes_premium',
  name: 'Chispas desde los Bordes Premium',
  publication: CreatorPublication.draft,
  description:
      'Chispas de núcleo caliente y estela de color que entran desde los bordes de la pantalla, se frenan y se apagan antes de llegar al centro, dejando libre la imagen. Sin fondo, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['energetic', 'intense', 'dynamic'],
  concepts: ['sparks', 'frame', 'light trails', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffd4145a, 0xffff5e3a, 0xffffd6b3],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas simuladas con física: fluidas a 30 FPS en el móvil.
  framesPerSecond: 30,
);
