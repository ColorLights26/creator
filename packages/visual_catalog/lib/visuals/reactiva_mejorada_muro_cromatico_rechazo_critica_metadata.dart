import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_muro_cromatico_rechazo_critica',
  name: 'Reactiva Mejorada · Muro Cromático (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con el golpe entra por un lado una gran masa de niebla de luz violeta eléctrico y naranja que se enrolla mientras avanza, con los colores fundidos en rosa intenso y volutas que cambian cada instante; al final se aclara desde dentro y se deshace. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['immersive', 'psychedelic', 'bold'],
  concepts: ['aparición momentánea', 'chromatic fog', 'color mass', 'volumetric light'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff7a1aff, 0xffff6a08, 0xfffff4f0],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
