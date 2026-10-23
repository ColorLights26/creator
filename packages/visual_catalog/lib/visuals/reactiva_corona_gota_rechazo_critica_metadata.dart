import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_corona_gota_rechazo_critica',
  name: 'Reactiva · Corona de Gota (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Con el golpe cae una gota de luz líquida y salpica en corona: anillo en perspectiva, pared translúcida de luz esmeralda con el borde rematado en puntas que sueltan gotitas, y un chorro que rebota en el centro. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['fluid', 'elegant', 'energetic'],
  concepts: ['aparición momentánea', 'crown splash', 'liquid light', 'high speed'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff00b060, 0xff30ff90, 0xfff0fff6],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
