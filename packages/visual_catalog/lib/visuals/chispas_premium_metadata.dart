import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'chispas_premium',
  name: 'Chispas Premium',
  publication: CreatorPublication.draft,
  description:
      'Chispas finas y rapidísimas de núcleo blanco y estela naranja que saltan de fuentes de fuego en abanico y caen en arco por su peso; con cada golpe, una fuente nueva. Sin fondo, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['energetic', 'intense', 'cinematic'],
  concepts: ['sparks', 'fire', 'streaks', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffff4a00, 0xffffa21f, 0xfffff0c8],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas simuladas con física: fluidas a 30 FPS en el móvil.
  framesPerSecond: 30,
);
