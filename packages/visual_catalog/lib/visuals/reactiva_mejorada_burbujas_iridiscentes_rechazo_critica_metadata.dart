import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_burbujas_iridiscentes_rechazo_critica',
  name: 'Reactiva Mejorada · Burbujas Iridiscentes (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con el golpe aparecen burbujas de jabón que suben bamboleándose, con bandas de color de interferencia que fluyen en la película, un reflejo blanco y el centro casi transparente; revientan una a una en un anillo de gotas. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['playful', 'dreamy', 'iridescent'],
  concepts: ['aparición momentánea', 'soap bubbles', 'thin film', 'iridescence'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff2a6a, 0xff30ff9a, 0xff4a6bff],
  images: {'noise': 'assets/images/reactiva_quemado.png'},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
