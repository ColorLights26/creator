import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'nubes_azules',
  name: 'Nubes Azules',
  publication: CreatorPublication.draft,
  description:
      'Nubes de humo azul que se mueven despacio, iluminadas por un foco de luz, con relámpagos de luz dentro con cada golpe. Sin fondo, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['mysterious', 'dreamy', 'dark'],
  concepts: ['clouds', 'smoke', 'blue light', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff0a1450, 0xff2338c8, 0xff7d93ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas simuladas con física: fluidas a 30 FPS en el móvil.
  framesPerSecond: 30,
);
