import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_vineta_late',
  name: 'Reactiva Mejorada · Viñeta que Late',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con el golpe, los bordes de la escena se oscurecen un instante, como si se mirara por un túnel, y el centro no se toca. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['subtle', 'rhythmic', 'cinematic'],
  concepts: ['aparición momentánea', 'vignette', 'tunnel', 'shadow pulse'],
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
