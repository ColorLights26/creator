import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_tinta_luz_rechazo_critica',
  name: 'Reactiva · Tinta de Luz (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Con el golpe se suelta tinta luminosa como en agua: dos tintas, escarlata y azul real, que brotan de un punto y se arremolinan en filamentos finos, sumándose en violeta donde se cruzan; se deshace adelgazando. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['fluid', 'elegant', 'mysterious'],
  concepts: ['aparición momentánea', 'ink in water', 'swirl', 'fluid light'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff2030, 0xff2a40ff, 0xfffff0f4],
  images: {'smoke': 'assets/images/reactiva_humo.png'},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
