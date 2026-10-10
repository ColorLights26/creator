import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'cascada_codigo',
  name: 'Cascada de Código',
  publication: CreatorPublication.draft,
  description:
      'Columnas de símbolos rojos con cabezas doradas que caen como el código de Matrix; aceleran con la energía y cada golpe enciende una onda.',
  purposes: ['visualizer', 'party', 'gaming'],
  moods: ['cyberpunk', 'intense', 'iconic'],
  concepts: ['digital rain', 'matrix', 'code', 'glyphs'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff000000, 0xffff1a1a, 0xffffc400, 0xffffffff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Caída continua: a 60 FPS las columnas bajan con fluidez.
  framesPerSecond: 30,
);
