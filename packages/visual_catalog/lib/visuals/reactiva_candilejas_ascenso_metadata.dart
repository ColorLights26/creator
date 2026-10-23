import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_candilejas_ascenso',
  name: 'Reactiva · Candilejas en Ascenso',
  publication: CreatorPublication.draft,
  description:
      'Durante la subida de energía cada bombo enciende una fila de focos en el borde inferior que lanzan conos de luz blanca cálida hacia arriba, más altos y más blancos cuanto más sube, que se recogen hacia abajo; en el drop se corta en seco. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['energetic', 'dramatic', 'warm'],
  concepts: ['aparición momentánea', 'footlights', 'uplights', 'stage haze', 'build-up'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.2),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff2a0a, 0xffffb31a, 0xfffff2dc],
  images: {'smoke': 'assets/images/reactiva_humo.png'},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
