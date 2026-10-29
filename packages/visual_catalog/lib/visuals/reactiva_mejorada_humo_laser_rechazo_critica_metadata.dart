import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_humo_laser_rechazo_critica',
  name: 'Reactiva Mejorada · Humo Láser (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con el golpe sube una columna de humo cortada por una lámina de láser azul: un hilo liso que empieza a ondular, se enrolla y se rompe arriba en una maraña de filamentos con un velo encendido; luego se despega y se deshace. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['strange', 'hypnotic', 'cool'],
  concepts: ['aparición momentánea', 'laser sheet', 'smoke plume', 'turbulence'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff3a14ff, 0xff7060ff, 0xfff0eeff],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
