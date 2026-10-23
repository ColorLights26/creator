import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_pulsar_rechazo_critica',
  name: 'Reactiva · Púlsar (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Con el golpe una estrella diminuta lanza dos haces opuestos de luz verde lima que giran como un faro y barren la pantalla con una estela en abanico; al final se acortan hasta apagarse. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['cosmic', 'energetic', 'hypnotic'],
  concepts: ['aparición momentánea', 'pulsar', 'lighthouse beams', 'magnetic field'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff20b000, 0xff9aff10, 0xfff4ffe0],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
