import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_cegadoras_cadena',
  name: 'Reactiva · Cegadoras en Cadena',
  publication: CreatorPublication.draft,
  description:
      'En el drop se encienden en cadena las cegadoras de concierto que hay justo encima del cuadro, con halo ámbar y un cono con humo, y al apagarse se enfrían de blanco a ámbar y a brasa. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['dramatic', 'energetic', 'warm'],
  concepts: ['aparición momentánea', 'audience blinders', 'concert lighting', 'tungsten'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.12),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffd8231a, 0xffffa31a, 0xfffff2dc],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece un instante con su momento.
  // Degradados, trazos y puntos agrupados: sin shaders por píxel.
  framesPerSecond: 30,
);
