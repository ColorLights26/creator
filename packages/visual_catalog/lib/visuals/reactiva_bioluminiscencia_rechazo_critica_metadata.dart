import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_bioluminiscencia_rechazo_critica',
  name: 'Reactiva · Bioluminiscencia (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Con el golpe una ola cruza la escena y se enciende el plancton: una cresta de espuma de luz azul rota en tramos con salpicaduras, y detrás puntos que destellan y se apagan en unos cuadros. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['calm', 'magical', 'cool'],
  concepts: ['aparición momentánea', 'bioluminescence', 'plankton', 'glow wave'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff1a40ff, 0xff3a8aff, 0xffe8f2ff],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
