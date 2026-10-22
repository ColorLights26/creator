import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_luz_bordes_transparente',
  name: 'Reactiva Mejorada · Luz de Bordes',
  publication: CreatorPublication.draft,
  description:
      'Versión reactiva mejorada: sin música no dibuja nada; con música se ve tanto como suena y cada golpe la enciende más. Resplandor de colores que recorre los bordes de la pantalla y se engrosa con cada banda de la música, con pulsos que corren con el ritmo sobre fondo transparente.',
  purposes: ['visualizer', 'party', 'ambient'],
  moods: ['modern', 'vivid', 'minimal'],
  concepts: ['aparición momentánea', 'reactiva mejorada', 'edge lighting', 'glow', 'spectrum', 'border'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.2),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff5e3a, 0xffd14bff, 0xff3dc8ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // El brillo corre por el borde sin parar: a 60 FPS es fluido.
  framesPerSecond: 30,
);
