import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_figura_lichtenberg_rechazo_critica',
  name: 'Reactiva Mejorada · Figura de Lichtenberg (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con el golpe una descarga dibuja desde un punto un árbol fractal de luz que se ramifica, blanco en el núcleo con resplandor lima y verde; parpadea y se recoge desde las puntas. Cada golpe dibuja un árbol distinto. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['electric', 'strange', 'intense'],
  concepts: ['aparición momentánea', 'lichtenberg figure', 'fractal', 'discharge'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff20ff40, 0xffb0ff20, 0xfff4ffe8],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
