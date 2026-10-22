import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'rio_particulas',
  name: 'Río de Partículas',
  publication: CreatorPublication.draft,
  description:
      'Un río de miles de partículas plateadas y carmesí que fluye serpenteando por la pantalla, con su resplandor, partículas que se escapan en remolinos y olas de luz que lo recorren con la música. Sin fondo, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['hypnotic', 'elegant', 'cosmic'],
  concepts: ['particle stream', 'river of light', 'flow', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff8f0019, 0xffff2d55, 0xfff4f0ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas simuladas con física: fluidas a 30 FPS en el móvil.
  framesPerSecond: 30,
);
