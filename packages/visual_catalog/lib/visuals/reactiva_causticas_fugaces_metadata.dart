import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_causticas_fugaces',
  name: 'Reactiva · Cáusticas Fugaces',
  publication: CreatorPublication.draft,
  description:
      'Cuando crecen los graves aparece por zonas la red de luz de una piscina, con líneas curvas brillantes, halo y borde prismático, y se evapora cuando bajan. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['fluid', 'dreamy', 'warm'],
  concepts: ['aparición momentánea', 'caustics', 'water light', 'bass'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.05),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff4a1a, 0xffffc04a, 0xfffff6e0],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece un instante con su momento.
  // Degradados, trazos y puntos agrupados: sin shaders por píxel.
  framesPerSecond: 30,
);
