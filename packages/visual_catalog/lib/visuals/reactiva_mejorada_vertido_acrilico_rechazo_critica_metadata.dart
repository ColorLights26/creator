import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_vertido_acrilico_rechazo_critica',
  name: 'Reactiva Mejorada · Vertido Acrílico (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con el golpe se vierte un charco de pintura de luz turquesa y rojo coral, como en el vertido acrílico: bandas estiradas que se curvan al extenderse y celdas de muchos tamaños por las que asoma el otro color; al final las celdas crecen hasta que no queda nada. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['fluid', 'artistic', 'psychedelic'],
  concepts: ['aparición momentánea', 'acrylic pour', 'fluid art', 'cells'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff00d0c0, 0xffff2a30, 0xfff8fff8],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
