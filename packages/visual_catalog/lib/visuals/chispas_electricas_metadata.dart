import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'chispas_electricas',
  name: 'Chispas Eléctricas',
  publication: CreatorPublication.draft,
  description:
      'Descargas eléctricas que chasquean por la pantalla: arcos en zigzag que se rehacen sin parar, con ramas, un halo violeta, un fogonazo donde golpean y una lluvia de chispas. Sin fondo, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['energetic', 'intense', 'futuristic'],
  concepts: ['electricity', 'lightning', 'sparks', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff3a0ca3, 0xff9d5cff, 0xfff1e8ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas simuladas con física: fluidas a 30 FPS en el móvil.
  framesPerSecond: 30,
);
