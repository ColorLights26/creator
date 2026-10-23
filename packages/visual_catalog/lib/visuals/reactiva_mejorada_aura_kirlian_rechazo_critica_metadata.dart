import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_aura_kirlian_rechazo_critica',
  name: 'Reactiva Mejorada · Aura Kirlian (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con el golpe aparece el aura eléctrica de una forma invisible, como en una fotografía Kirlian: decenas de filamentos de descarga violeta y magenta que brotan de un contorno que no se ve, cambian sin parar y se acortan hasta desaparecer. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['strange', 'electric', 'mystic'],
  concepts: ['aparición momentánea', 'kirlian', 'corona discharge', 'aura'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff8a2aff, 0xffff2ad0, 0xfff6f0ff],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
