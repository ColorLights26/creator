import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_cadena_iris',
  name: 'Reactiva · Cadena de Iris',
  publication: CreatorPublication.draft,
  description:
      'Con el bombo, una luz fuera del cuadro hace que la lente proyecte su cadena de fantasmas heptagonales con los tintes rojo, verde y ámbar de los recubrimientos. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['cinematic', 'vintage', 'rhythmic'],
  concepts: ['aparición momentánea', 'lens flare', 'iris ghosts', 'aperture'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.04),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff3b30, 0xff39ff88, 0xffffb02a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece un instante con su momento.
  // Degradados, trazos y puntos agrupados: sin shaders por píxel.
  framesPerSecond: 30,
);
