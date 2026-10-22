import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_chispas_premium',
  name: 'Reactiva Mejorada · Chispas Premium',
  publication: CreatorPublication.draft,
  description:
      'Versión reactiva mejorada: sin música no dibuja nada; con música se ve tanto como suena y cada golpe la enciende más. Chispas finas y rapidísimas de núcleo blanco y estela naranja que saltan de fuentes de fuego en abanico y caen en arco por su peso; con cada golpe, una fuente nueva. Sin fondo, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['energetic', 'intense', 'cinematic'],
  concepts: ['aparición momentánea', 'reactiva mejorada', 'sparks', 'fire', 'streaks', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.2),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff4a00, 0xffffa21f, 0xfffff0c8],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas simuladas con física: fluidas a 30 FPS en el móvil.
  framesPerSecond: 30,
);
