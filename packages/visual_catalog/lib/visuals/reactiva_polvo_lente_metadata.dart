import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_polvo_lente',
  name: 'Reactiva · Polvo de Lente Revelado',
  publication: CreatorPublication.draft,
  description:
      'En el golpe grande una luz fuera de cuadro barre la lente y revela la suciedad del cristal cerca de ella: motas, huellas, pelos y un velo cálido. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['cinematic', 'elegant', 'warm'],
  concepts: ['aparición momentánea', 'lens dirt', 'lens flare', 'optics'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.3),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff5a3a, 0xffffb050, 0xfffff0dc],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece un instante con su momento.
  // Degradados, trazos y puntos agrupados: sin shaders por píxel.
  framesPerSecond: 30,
);
