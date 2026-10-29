import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_carrera_neon_rechazo_critica',
  name: 'Reactiva Mejorada · Carrera de Neón (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con el golpe dos cometas de neón recorren el contorno redondeado de la pantalla en sentidos opuestos, con núcleo blanco y estela roja anaranjada que se apaga, y se desvanecen al cruzarse. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['club', 'energetic', 'graphic'],
  concepts: ['aparición momentánea', 'neon', 'led chase', 'edge light'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff1a20, 0xffff6a10, 0xfffff2ea],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
