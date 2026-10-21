import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_golpe_cine',
  name: 'Reactiva · Golpe de Cine',
  publication: CreatorPublication.draft,
  description:
      'En el golpe grande, unas franjas negras finas entran desde arriba y desde abajo, como en una película, y se retiran enseguida. Encuadra la escena un instante sin tocar su contenido. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['subtle', 'cinematic', 'dramatic'],
  concepts: ['aparición momentánea', 'letterbox', 'cinema bars', 'impact'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.1),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff000000, 0xffffd6a0, 0xfffff7ea],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece un instante con su momento. Dibuja como mucho unos rectángulos con degradado.
  framesPerSecond: 30,
);
