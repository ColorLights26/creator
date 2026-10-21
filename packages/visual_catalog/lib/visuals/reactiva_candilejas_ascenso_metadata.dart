import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_candilejas_ascenso',
  name: 'Reactiva · Candilejas en Ascenso',
  publication: CreatorPublication.draft,
  description:
      'Durante la subida de energía, cada bombo enciende un pulso de candilejas bajo el cuadro, con conos y humo que trepan más alto y más blancos cuanto más sube; en el drop se corta. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['energetic', 'warm', 'building'],
  concepts: ['aparición momentánea', 'footlights', 'build-up', 'stage lighting'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.16),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffd8231a, 0xffffa31a, 0xfffff2dc],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece un instante con su momento.
  // Degradados, trazos y puntos agrupados: sin shaders por píxel.
  framesPerSecond: 30,
);
