import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_onda_cristal',
  name: 'Reactiva Mejorada · Onda en el Cristal',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con el bombo se abren ondas rápidas como en una lámina de agua sobre la escena: cresta de luz y valle de sombra, que se leen como refracción, y se apagan enseguida. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['subtle', 'fluid', 'rhythmic'],
  concepts: ['aparición momentánea', 'ripple', 'water', 'refraction'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.15),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff000000, 0xffffc680, 0xfffff4e4],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece un instante con su momento.
  // Degradados, trazos y puntos agrupados: sin shaders por píxel.
  framesPerSecond: 30,
);
