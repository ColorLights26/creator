import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_hiperespacio_premium',
  name: 'Reactiva Mejorada · Hiperespacio Premium',
  publication: CreatorPublication.draft,
  description:
      'Versión reactiva mejorada: sin música no dibuja nada; con música se ve tanto como suena y cada golpe la enciende más. Salto al hiperespacio: estrellas que nacen tenues en el centro y salen disparadas hacia los bordes, acelerando y estirándose en rayos de luz. Sin fondo, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['epic', 'futuristic', 'energetic'],
  concepts: ['aparición momentánea', 'reactiva mejorada', 'hyperspace', 'warp', 'light speed', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.2),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff3d5cff, 0xffbfd0ff, 0xffffffff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas simuladas con física: fluidas a 30 FPS en el móvil.
  framesPerSecond: 30,
);
