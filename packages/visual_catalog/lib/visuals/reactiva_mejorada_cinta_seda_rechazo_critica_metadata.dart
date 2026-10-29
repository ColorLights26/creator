import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_cinta_seda_rechazo_critica',
  name: 'Reactiva Mejorada · Cinta de Seda (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con el golpe una cinta ancha de seda de luz esmeralda se despliega de lado a lado ondeando en una S: los pliegues atrapan brillos blancos que corren por la tela y el filo brilla; se va estrechando hasta desaparecer. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['elegant', 'fluid', 'luxurious'],
  concepts: ['aparición momentánea', 'silk', 'ribbon', 'fabric light'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff00c050, 0xff30ff80, 0xfff0fff4],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
