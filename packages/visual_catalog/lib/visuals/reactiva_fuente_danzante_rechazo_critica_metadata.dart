import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_fuente_danzante_rechazo_critica',
  name: 'Reactiva · Fuente Danzante (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Con el golpe una fila de surtidores lanza chorros de agua iluminados como en un espectáculo de fuentes: columnas y arcos que se cruzan, que suben continuos y arriba se rompen en lluvia de gotas, azul cobalto y blanco. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['elegant', 'festive', 'cool'],
  concepts: ['aparición momentánea', 'musical fountain', 'water show', 'light'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff1a3aff, 0xff5a8aff, 0xfff6f9ff],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
