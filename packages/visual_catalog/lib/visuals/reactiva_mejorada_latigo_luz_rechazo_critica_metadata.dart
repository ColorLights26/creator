import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_latigo_luz_rechazo_critica',
  name: 'Reactiva Mejorada · Látigo de Luz (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con el golpe un látigo de luz roja y naranja barre un arco desde un borde dejando una estela en abanico, un bucle rueda hasta la punta y restalla con un chasquido de luz, rayos, un anillo de choque y chispas; luego se apaga desde el mango. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['energetic', 'dramatic', 'intense'],
  concepts: ['aparición momentánea', 'whip crack', 'sonic boom', 'light stroke'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff1a08, 0xffff7a00, 0xfffff4c8],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
