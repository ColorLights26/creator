import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_banda_obturador',
  name: 'Reactiva · Banda de Obturador',
  publication: CreatorPublication.draft,
  description:
      'Con la caja aparece el artefacto de un flash grabado con obturador rodante: en un cuadro se ilumina una franja con corte nítido y en el siguiente la parte complementaria. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['subtle', 'rhythmic', 'bright'],
  concepts: ['aparición momentánea', 'rolling shutter', 'camera flash', 'exposure'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.59),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff4a3a, 0xffd8e6ff, 0xfff6f9ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece un instante con su momento.
  // Degradados, trazos y puntos agrupados: sin shaders por píxel.
  framesPerSecond: 30,
);
