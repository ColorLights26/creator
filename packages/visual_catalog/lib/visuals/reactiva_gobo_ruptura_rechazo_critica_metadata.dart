import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_gobo_ruptura_rechazo_critica',
  name: 'Reactiva · Gobo de Ruptura (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Con el golpe aparece el círculo de un foco con gobo de ruptura: una docena de manchas de luz de bordes enfocados que giran mientras el círculo se desliza, blanco azulado en el centro y azul intenso hacia el borde; se cierra como un iris. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['cinematic', 'cool', 'energetic'],
  concepts: ['aparición momentánea', 'gobo', 'moving head', 'breakup light'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff2a50ff, 0xff6a9cff, 0xfff0f4ff],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
