import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_primer_tiempo',
  name: 'Reactiva Mejorada · Primer Tiempo',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Sólo en el primer pulso de cada compás la escena se oscurece o se aclara un instante y vuelve: marca el ritmo sin parpadear en cada golpe. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['subtle', 'rhythmic', 'minimal'],
  concepts: ['aparición momentánea', 'downbeat', 'bar', 'pulse'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.08),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff000000, 0xffffd6a0, 0xfffff7ea],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece un instante con su momento. Dibuja como mucho unos rectángulos con degradado.
  framesPerSecond: 30,
);
