import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'lluvia_dorada_premium',
  name: 'Lluvia Dorada Premium',
  publication: CreatorPublication.draft,
  description:
      'Purpurina de oro que cae girando: casi siempre tenue y, al darle la luz, destella con rayos finos, con luces de oro desenfocadas. Sin fondo, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['glamorous', 'festive', 'elegant'],
  concepts: ['glitter', 'gold', 'sparkles', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff8a5a00, 0xffffbf2e, 0xfffff2c8],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas simuladas con física: fluidas a 30 FPS en el móvil.
  framesPerSecond: 30,
);
