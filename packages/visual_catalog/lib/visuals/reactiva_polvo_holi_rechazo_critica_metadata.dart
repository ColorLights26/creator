import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_polvo_holi_rechazo_critica',
  name: 'Reactiva · Polvo Holi (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Con el golpe estallan nubes de polvo de color (rojo, naranja y amarillo encendido) que se abren rápido, turbulentas, con el núcleo brillante y los bordes en jirones, y luego se deshacen. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['festive', 'warm', 'explosive'],
  concepts: ['aparición momentánea', 'holi powder', 'color burst', 'dust cloud'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff1e10, 0xffff6a00, 0xffffc800],
  images: {'smoke': 'assets/images/reactiva_humo.png'},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
