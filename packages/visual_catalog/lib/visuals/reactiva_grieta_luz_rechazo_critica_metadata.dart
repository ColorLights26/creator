import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_grieta_luz_rechazo_critica',
  name: 'Reactiva · Grieta de Luz (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Con el golpe la pantalla se raja como un cristal desde un punto: grietas quebradas que corren hacia fuera y anillos que las unen como una tela de araña, con luz blanca, ámbar y roja; se enfrían y se apagan desde las puntas. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['dramatic', 'intense', 'cinematic'],
  concepts: ['aparición momentánea', 'glass crack', 'fracture', 'light leak'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff3010, 0xffffa020, 0xfffff6ea],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
