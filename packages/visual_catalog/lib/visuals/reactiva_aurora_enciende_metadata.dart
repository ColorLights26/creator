import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_aurora_enciende',
  name: 'Reactiva · Aurora que se Enciende',
  publication: CreatorPublication.draft,
  description:
      'Durante la subida de energía baja desde arriba la cortina de una aurora boreal: cinta ondulada con pliegues que brillan de canto, rayos verticales finos, borde verde intenso con franja magenta debajo y carmesí arriba; en el pico brilla el doble y se retira. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['dreamy', 'cosmic', 'vivid'],
  concepts: ['aparición momentánea', 'aurora borealis', 'curtain', 'rays'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.4),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff1e3c, 0xff30ff4a, 0xffff2ad0],
  images: {'noise': 'assets/images/reactiva_quemado.png'},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
