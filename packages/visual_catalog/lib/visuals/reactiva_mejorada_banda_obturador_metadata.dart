import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_banda_obturador',
  name: 'Reactiva Mejorada · Banda de Obturador',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con la caja aparece el artefacto de un flash grabado con obturador rodante: en un cuadro se ilumina una franja con corte nítido, con línea brillante y filo rojo en el corte, y en el siguiente la parte complementaria. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['energetic', 'raw', 'documentary'],
  concepts: ['aparición momentánea', 'rolling shutter', 'camera flash', 'sensor artifact'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff4a3a, 0xffd8e6ff, 0xfff6f9ff],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
