import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_hilos_corriente_rechazo_critica',
  name: 'Reactiva Mejorada · Hilos de Corriente (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con el golpe entra un peine de hilos de humo luminoso azul eléctrico e índigo, como en un túnel de viento: se apartan al pasar junto a obstáculos invisibles y detrás ondean y se deshilachan; al cortarse, la cola se va con la corriente. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['fluid', 'elegant', 'cool'],
  concepts: ['aparición momentánea', 'wind tunnel', 'smoke streaklines', 'flow visualization'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff3a1aff, 0xff1a6aff, 0xfff0f4ff],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
