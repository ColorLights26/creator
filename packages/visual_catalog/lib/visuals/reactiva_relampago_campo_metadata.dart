import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_relampago_campo',
  name: 'Reactiva · Relámpago Fuera de Campo',
  publication: CreatorPublication.draft,
  description:
      'No se ve el rayo: en el golpe grande entra desde una esquina la luz de una tormenta fuera de plano, con descarga, re-descarga, segundo rayo desde otro punto y cola que titila; blanca cerca, azul y violeta lejos, con nubes que se encienden por el borde y rayos entre ellas. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['dramatic', 'dark', 'cinematic'],
  concepts: ['aparición momentánea', 'lightning', 'storm', 'off-screen light', 'clouds'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff7a1eff, 0xff6a8cff, 0xfff2f6ff],
  images: {'smoke': 'assets/images/reactiva_humo.png'},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
