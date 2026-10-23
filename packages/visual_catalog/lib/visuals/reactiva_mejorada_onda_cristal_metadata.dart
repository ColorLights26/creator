import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_onda_cristal',
  name: 'Reactiva Mejorada · Onda en el Cristal',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con el bombo se abren sobre la escena ondas rápidas como en una lámina de agua: cada anillo con cresta de luz fina y valle de sombra justo dentro, que se leen como refracción, y que se amortiguan y apagan en medio segundo. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['calm', 'elegant', 'fluid'],
  concepts: ['aparición momentánea', 'ripple', 'refraction', 'water'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff000000, 0xffffc680, 0xfffff4e4],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
