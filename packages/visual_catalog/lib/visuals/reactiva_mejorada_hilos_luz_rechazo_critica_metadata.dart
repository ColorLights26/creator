import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_hilos_luz_rechazo_critica',
  name: 'Reactiva Mejorada · Hilos de Luz (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con el golpe se tienden 160 hilos de luz entre puntos de un círculo y, donde se cruzan, dibujan una curva brillante (cardioide, nefroide o flor) distinta en cada golpe, que gira y fluye; se recoge cerrándose hacia el centro. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['elegant', 'hypnotic', 'geometric'],
  concepts: ['aparición momentánea', 'string art', 'cardioid', 'times tables'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff1a3a, 0xffff5a1a, 0xfffff2ea],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
