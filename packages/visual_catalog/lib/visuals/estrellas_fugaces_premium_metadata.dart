import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'estrellas_fugaces_premium',
  name: 'Estrellas Fugaces Premium',
  publication: CreatorPublication.draft,
  description:
      'Estrellas fugaces de verdad: una cabeza blanca con resplandor y una cola larga que se afina y se apaga cruzan en diagonal sobre un cielo de estrellas que titilan; con cada golpe cruza otra. Sin fondo, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['magical', 'dreamy', 'calm'],
  concepts: ['shooting stars', 'meteors', 'night sky', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff6f90ff, 0xffdde6ff, 0xffffffff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas simuladas con física: fluidas a 30 FPS en el móvil.
  framesPerSecond: 30,
);
