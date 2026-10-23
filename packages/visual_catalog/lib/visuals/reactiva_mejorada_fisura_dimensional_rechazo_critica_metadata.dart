import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_fisura_dimensional_rechazo_critica',
  name: 'Reactiva Mejorada · Fisura Dimensional (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con el golpe se rasga el aire: una grieta alargada se abre como un ojo, con bordes dentados de luz blanca que tiemblan, energía violeta que corre dentro, rayos que escapan y motas absorbidas; al final se cierra encogiéndose. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['strange', 'dramatic', 'mystic'],
  concepts: ['aparición momentánea', 'dimensional rift', 'tear', 'energy'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff5a10ff, 0xffa070ff, 0xfff6f0ff],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
