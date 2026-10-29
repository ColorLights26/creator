import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_desplome_rechazo_critica',
  name: 'Reactiva · Desplome (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Con el golpe una columna de líquido luminoso mandarina, ya inclinada y cayendo, se derrumba en dos oleadas de cabezas abultadas que corren por el tercio de abajo, ámbar donde es más gruesa; la película se vacía desde las colas. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['dramatic', 'fluid', 'warm'],
  concepts: ['aparición momentánea', 'dam break', 'liquid collapse', 'surge'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff2a04, 0xffff6a00, 0xfffff2d0],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
