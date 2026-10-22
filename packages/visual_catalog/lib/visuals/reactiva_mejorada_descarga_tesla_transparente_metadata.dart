import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_descarga_tesla_transparente',
  name: 'Reactiva Mejorada · Descarga Tesla',
  publication: CreatorPublication.draft,
  description:
      'Versión reactiva mejorada: sin música no dibuja nada; con música se ve tanto como suena y cada golpe la enciende más. Plasma eléctrico a pantalla completa: rayos ramificados desde un núcleo de energía que siguen el espectro y estallan con cada golpe sobre fondo transparente.',
  purposes: ['party', 'visualizer'],
  moods: ['electric', 'energetic', 'mysterious'],
  concepts: ['aparición momentánea', 'reactiva mejorada', 'plasma', 'electricity', 'tesla', 'lightning'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.2),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffd64bff, 0xff4f6dff, 0xffffd6f6],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
