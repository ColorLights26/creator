import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_latido_oscuro',
  name: 'Reactiva · Latido Oscuro',
  publication: CreatorPublication.draft,
  description:
      'Con cada bombo toda la escena se oscurece un poco durante una décima de segundo y vuelve, como el sidechain de la música electrónica. No añade nada: sólo baja la luz de lo que haya detrás. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['subtle', 'rhythmic', 'dark'],
  concepts: ['aparición momentánea', 'sidechain', 'pump', 'shadow pulse'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.05),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff000000, 0xffffd6a0, 0xfffff7ea],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece un instante con su momento. Dibuja como mucho unos rectángulos con degradado.
  framesPerSecond: 30,
);
