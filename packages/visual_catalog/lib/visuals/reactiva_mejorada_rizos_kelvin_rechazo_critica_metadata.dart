import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_rizos_kelvin_rechazo_critica',
  name: 'Reactiva Mejorada · Rizos de Kelvin (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con el golpe se enciende a lo ancho la frontera entre dos corrientes de luz, turquesa y rosa intenso, que se enrolla en una fila de rizos de tamaños distintos como las olas de Kelvin-Helmholtz; crecen, avanzan y se rompen hasta deshacerse. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['fluid', 'hypnotic', 'cool'],
  concepts: ['aparición momentánea', 'kelvin helmholtz', 'shear flow', 'billows'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff00d8c8, 0xffff1a8a, 0xfff8f4ff],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
