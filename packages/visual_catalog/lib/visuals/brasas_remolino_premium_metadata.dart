import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'brasas_remolino_premium',
  name: 'Brasas en Remolino Premium',
  publication: CreatorPublication.draft,
  description:
      'Un torbellino de aire caliente: brasas con núcleo caliente y estela naranja que suben girando en un embudo que se abre, entre un humo rojizo. Sin fondo, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['intense', 'hypnotic', 'warm'],
  concepts: ['embers', 'vortex', 'smoke', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffb81408, 0xffff7a12, 0xffffd27a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas simuladas con física: fluidas a 30 FPS en el móvil.
  framesPerSecond: 30,
);
