import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_borde_luz',
  name: 'Reactiva Mejorada · Borde de Luz',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con los platillos, los bordes de la escena se aclaran un instante con una luz cálida y el centro no se toca. En modo Alterno la luz entra por un lado y luego por el otro. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['subtle', 'rhythmic', 'warm'],
  concepts: ['aparición momentánea', 'edge light', 'hi-hat', 'light pulse'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.36),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff000000, 0xffffd6a0, 0xfffff7ea],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece un instante con su momento. Dibuja como mucho unos rectángulos con degradado.
  framesPerSecond: 30,
);
