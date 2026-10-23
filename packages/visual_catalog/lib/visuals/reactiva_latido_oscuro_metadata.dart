import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_latido_oscuro',
  name: 'Reactiva · Latido Oscuro',
  publication: CreatorPublication.draft,
  description:
      'Con cada bombo toda la escena baja de luz como con un compresor: a fondo en el mismo golpe, se sostiene un cuadro y vuelve suave, primero en el centro, con cada golpe un poco distinto; también puede oscurecer sólo los bordes. No añade nada. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['energetic', 'minimal', 'dark'],
  concepts: ['aparición momentánea', 'sidechain', 'pump', 'darkening'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff000000, 0xffffc27a, 0xfffff7ea],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
