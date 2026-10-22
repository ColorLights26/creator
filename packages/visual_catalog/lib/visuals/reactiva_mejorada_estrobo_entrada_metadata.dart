import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_estrobo_entrada',
  name: 'Reactiva Mejorada · Estrobo de Entrada',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. En el golpe grande, de uno a tres parpadeos tenues de luz o de sombra y nada más: la versión suave del estroboscopio, nunca más de tres por segundo. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['subtle', 'energetic', 'bright'],
  concepts: ['aparición momentánea', 'strobe', 'drop', 'flash'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.04),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff000000, 0xffffd6a0, 0xfffff7ea],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece un instante con su momento. Dibuja como mucho unos rectángulos con degradado.
  framesPerSecond: 30,
);
