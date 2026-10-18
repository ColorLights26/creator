import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'brasas_remolino',
  name: 'Brasas en Remolino',
  publication: CreatorPublication.draft,
  description:
      'Capa transparente de brasas en remolino: chispas de fuego que suben girando alrededor del centro como en un torbellino de aire caliente, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['intense', 'hypnotic', 'warm'],
  concepts: ['embers', 'vortex', 'fire', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffc81d11, 0xffff8c1a, 0xffffe08a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas sencillas: a 30 FPS gastan poca batería.
  framesPerSecond: 30,
);
