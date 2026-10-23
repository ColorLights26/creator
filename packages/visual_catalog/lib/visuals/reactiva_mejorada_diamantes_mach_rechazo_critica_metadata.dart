import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_diamantes_mach_rechazo_critica',
  name: 'Reactiva Mejorada · Diamantes de Mach (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con el golpe entra desde un borde un chorro supersónico con una fila de diamantes de choque, celdas de luz en rombo amarillas y blancas unidas por un chorro naranja que acaba en una cola turbulenta; se apaga recogiéndose hacia el borde. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['powerful', 'intense', 'energetic'],
  concepts: ['aparición momentánea', 'mach diamonds', 'shock diamonds', 'exhaust plume'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff1a10, 0xffff6a00, 0xfffff2d0],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
