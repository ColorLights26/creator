import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_estrella_difraccion',
  name: 'Reactiva Mejorada · Estrella de Difracción',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con la caja se abre en un punto alto la estrella de una lente ante una luz fuerte: núcleo quemado, picos que salen disparados y se recogen desde la punta, blancos junto al núcleo y en bandas de azul, verde y rojo hacia fuera, con anillos de Airy al principio. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['cosmic', 'elegant', 'cinematic'],
  concepts: ['aparición momentánea', 'diffraction spikes', 'airy rings', 'optics', 'starburst'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff2a10, 0xff30ff70, 0xff3a6bff],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
