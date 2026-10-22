import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_show_laser_transparente',
  name: 'Reactiva Mejorada · Show Láser',
  publication: CreatorPublication.draft,
  description:
      'Versión reactiva mejorada: sin música no dibuja nada; con música se ve tanto como suena y cada golpe la enciende más. Espectáculo de láseres de festival: abanicos de rayos de colores que barren el humo, se abren y destellan con cada golpe sobre fondo transparente.',
  purposes: ['party', 'visualizer'],
  moods: ['epic', 'energetic', 'club'],
  concepts: ['aparición momentánea', 'reactiva mejorada', 'lasers', 'beams', 'festival', 'light show'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.2),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff1e5a, 0xff2bff6a, 0xff1ec8ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
