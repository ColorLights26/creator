import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_golpe_cine',
  name: 'Reactiva · Golpe de Cine',
  publication: CreatorPublication.draft,
  description:
      'En el golpe grande la escena se encuadra un instante como una película: franjas negras finas que entran deslizándose con el borde suave y un hilo de luz cálida en el filo, y se retiran enseguida. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['cinematic', 'dramatic', 'minimal'],
  concepts: ['aparición momentánea', 'letterbox', 'cinema', 'framing'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff000000, 0xffffc27a, 0xfffff7ea],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
