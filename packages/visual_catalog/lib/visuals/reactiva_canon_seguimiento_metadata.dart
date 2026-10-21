import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_canon_seguimiento',
  name: 'Reactiva · Cañón de Seguimiento',
  publication: CreatorPublication.draft,
  description:
      'Tras una pausa, en el primer golpe se abre de golpe el iris de un cañón de seguimiento: luz cálida dentro, la escena algo más oscura fuera, y se cierra al poco. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['cinematic', 'dramatic', 'warm'],
  concepts: ['aparición momentánea', 'followspot', 'iris', 'spotlight'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.3),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff000000, 0xffd8e4ff, 0xfffff0d6],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece un instante con su momento.
  // Degradados, trazos y puntos agrupados: sin shaders por píxel.
  framesPerSecond: 30,
);
