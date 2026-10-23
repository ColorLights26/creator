import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_cadena_iris',
  name: 'Reactiva · Cadena de Iris',
  publication: CreatorPublication.draft,
  description:
      'Con el bombo, una luz que entra por el borde hace que la lente proyecte su cadena de fantasmas del diafragma hacia el centro: polígonos casi transparentes con aro suave, filo de color y polvo, en rojo, verde y violeta, que se deslizan con la luz y se apagan. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['cinematic', 'elegant', 'vivid'],
  concepts: ['aparición momentánea', 'lens ghosts', 'iris', 'lens flare', 'optics'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff2a3a, 0xff30ff70, 0xff4a5bff],
  images: {'dirt': 'assets/images/reactiva_suciedad_lente.png'},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
