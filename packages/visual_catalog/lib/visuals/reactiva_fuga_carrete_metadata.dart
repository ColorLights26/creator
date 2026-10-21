import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_fuga_carrete',
  name: 'Reactiva · Fuga de Luz de Carrete',
  publication: CreatorPublication.draft,
  description:
      'Al empezar una frase entra desde un borde una fuga de luz cálida y orgánica, como la de una cámara de película, que se desplaza, respira y se va, con grano encima. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['warm', 'vintage', 'dreamy'],
  concepts: ['aparición momentánea', 'light leak', 'film', 'analog'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.5),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff3b1f, 0xffff8a00, 0xffffe8b0],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece un instante con su momento.
  // Degradados, trazos y puntos agrupados: sin shaders por píxel.
  framesPerSecond: 30,
);
