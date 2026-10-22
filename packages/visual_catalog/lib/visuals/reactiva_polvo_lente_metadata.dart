import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_polvo_lente',
  name: 'Reactiva · Polvo de Lente Revelado',
  publication: CreatorPublication.draft,
  description:
      'Una luz cálida e intensa cruza la lente en un arco y revela a su alrededor la suciedad real del cristal: manchas, huellas, vetas de grasa, fibras y motas con borde cromático, con una estela anamórfica azul y fantasmas suaves del diafragma que se mueven al revés que la luz. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['cinematic', 'elegant', 'vivid'],
  concepts: ['aparición momentánea', 'lens dirt', 'anamorphic streak', 'lens ghosts', 'optics'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.3),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x003c8cff, 0xffff6a00, 0xffff2a2a, 0xffffa31a],
  images: {'dirt': 'assets/images/reactiva_suciedad_lente.png'},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
