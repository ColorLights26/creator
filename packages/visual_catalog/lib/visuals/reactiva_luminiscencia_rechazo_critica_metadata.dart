import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_luminiscencia_rechazo_critica',
  name: 'Reactiva · Luminiscencia (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Con el golpe se mezclan dos líquidos invisibles y sólo donde se tocan se enciende la luz, como en una barra luminosa: velos y remolinos de verde lima que se enroscan y se doblan; al agotarse se adelgazan y se encogen. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['strange', 'fluid', 'electric'],
  concepts: ['aparición momentánea', 'chemiluminescence', 'glow reaction', 'mixing'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff40a000, 0xffa8ff10, 0xfff8ffe0],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
