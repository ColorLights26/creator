import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_aurora_enciende',
  name: 'Reactiva Mejorada · Aurora que se Enciende',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Durante la subida de energía baja desde arriba una cortina de rayos de aurora, esmeralda con borde rosado y cresta carmesí; en el drop brilla el doble y se retira hacia arriba. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['magical', 'building', 'vivid'],
  concepts: ['aparición momentánea', 'aurora', 'build-up', 'curtain of light'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.2),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffe0103a, 0xff1fff8a, 0xffffc8e4],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece un instante con su momento.
  // Degradados, trazos y puntos agrupados: sin shaders por píxel.
  framesPerSecond: 30,
);
