import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_causticas_fugaces',
  name: 'Reactiva · Cáusticas Fugaces',
  publication: CreatorPublication.draft,
  description:
      'Cuando crecen los graves aparece por zonas la red de luz que el sol dibuja a través del agua: filamentos finos y curvos que se mueven, dorados en los nudos y ámbar en los finos, con borde prismático, y se evapora cuando bajan. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['dreamy', 'warm', 'calm'],
  concepts: ['aparición momentánea', 'caustics', 'water light', 'pool'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.4),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff4a1a, 0xffffc04a, 0xfffff6e0],
  images: {'noise': 'assets/images/reactiva_quemado.png'},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
