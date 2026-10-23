import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_calle_vortices',
  name: 'Reactiva · Calle de Vórtices (aprobada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Con el golpe algo invisible cruza la escena y deja una calle de remolinos de luz: dos hilos de tinte, carmesí y ámbar, que se enrollan en espirales alternas, cada vez más difusas, como el humo detrás de un cilindro; se borra desde el extremo más viejo. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['fluid', 'hypnotic', 'warm'],
  concepts: ['aparición momentánea', 'von karman', 'vortex street', 'flow visualization'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff1a30, 0xffffa020, 0xfffff0d0],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
