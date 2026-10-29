import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_laser_espejos_rechazo_critica',
  name: 'Reactiva · Láser de Espejos (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Con el golpe un rayo láser verde rebota entre espejos invisibles alrededor de la escena y dibuja en un instante una estrella de líneas con un destello en cada espejo; luego se recoge desde el principio. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['club', 'geometric', 'energetic'],
  concepts: ['aparición momentánea', 'laser', 'mirror bounce', 'star polygon'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff00b030, 0xff30ff50, 0xffeaffee],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
