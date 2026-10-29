import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_salpicadura_uv_rechazo_critica',
  name: 'Reactiva · Salpicadura UV (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Con el golpe aparece una salpicadura de pintura fluorescente que brilla como bajo luz negra: mancha con espesor, gotas y regueros en verde neón, naranja o violeta UV, con halo; se apaga encogiéndose. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['party', 'neon', 'playful'],
  concepts: ['aparición momentánea', 'uv paint', 'blacklight', 'splatter'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff39ff14, 0xffff6a00, 0xff8a2aff],
  images: {'noise': 'assets/images/reactiva_quemado.png'},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
