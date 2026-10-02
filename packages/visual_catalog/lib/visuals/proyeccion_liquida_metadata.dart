import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'proyeccion_liquida',
  name: 'Proyección Líquida',
  publication: CreatorPublication.draft,
  description:
      'Espectáculo de luz líquida: tintes de aceite que se mezclan en el proyector, se presionan con cada golpe y ondulan con los graves.',
  purposes: ['party', 'visualizer'],
  moods: ['psychedelic', 'retro', 'fluid'],
  concepts: ['liquid light show', 'oil', 'dye', 'projector'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff050308, 0xffff2d95, 0xff00c2ff, 0xffffd23f],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
