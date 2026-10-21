import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_cortina_svoboda',
  name: 'Reactiva · Cortina Svoboda',
  publication: CreatorPublication.draft,
  description:
      'Al empezar una frase se materializa desde arriba una lámina de decenas de rayos casi paralelos, con venas brillantes y polvo dentro, y se disuelve hacia arriba. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['elegant', 'cinematic', 'warm'],
  concepts: ['aparición momentánea', 'light curtain', 'svoboda', 'volumetric light'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.15),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff4a1a, 0xffffb44a, 0xfffff2e0],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece un instante con su momento.
  // Degradados, trazos y puntos agrupados: sin shaders por píxel.
  framesPerSecond: 30,
);
