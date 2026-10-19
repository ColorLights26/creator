import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'brasas_azules_premium',
  name: 'Brasas Azules Premium',
  publication: CreatorPublication.draft,
  description:
      'Chispas de fuego frío que suben con una estela larga desde una bruma azul que respira, con núcleo casi blanco y halo azul; las cercanas, desenfocadas. Sin fondo, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['cool', 'mysterious', 'cinematic'],
  concepts: ['blue embers', 'sparks', 'mist', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff0a2fd6, 0xff1e8fff, 0xffc4ecff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas simuladas con física: fluidas a 30 FPS en el móvil.
  framesPerSecond: 30,
);
