import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_flash_palmada',
  name: 'Reactiva Mejorada · Flash de Palmada',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Sólo con la caja o la palmada salta el flash de una cámara a lo lejos: un punto quemado, una estrella óptica que gira un poco en cada flash y un resplandor azul frío que cae rápido, a pleno en el mismo golpe y apagado al tercer cuadro. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['energetic', 'documentary', 'crisp'],
  concepts: ['aparición momentánea', 'camera flash', 'clap', 'paparazzi'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff000000, 0xff6a9cff, 0xfff4f8ff],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
