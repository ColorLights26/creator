import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_chorro_criogenico_rechazo_critica',
  name: 'Reactiva · Chorro Criogénico (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'En el golpe disparan desde abajo de dos a cuatro chorros de CO2: núcleo blanco que sale de la boquilla y columna turbulenta con filo violeta; al cortarse, la niebla sube y se deshace en jirones. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['energetic', 'festival', 'cool'],
  concepts: ['aparición momentánea', 'co2 jet', 'cryo', 'stage effects'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xfff2f6ff, 0xff8a2aff, 0xff4a2aff],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
