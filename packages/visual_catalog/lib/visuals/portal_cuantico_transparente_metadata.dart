import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'portal_cuantico_transparente',
  name: 'Portal Cuántico Transparente',
  publication: CreatorPublication.draft,
  description:
      'Túnel hipnótico de geometría sagrada fractal con anillos neón sobre fondo transparente.',
  purposes: ['visualizer', 'party', 'meditation'],
  moods: ['hypnotic', 'trippy', 'electric'],
  concepts: ['fractal', 'sacred_geometry', 'tunnel', 'quantum', 'neon'],
  credits: CreatorCredits(
    author: 'Color Lights 26',
    license: 'Proprietary',
    source: 'Color Lights Studio',
  ),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3.0),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xFF38E1FF, 0xFFF33D98, 0xFFFFDF00],
  controls: CreatorControls(intensity: 1.0, speed: 1.0, detail: 1.0, glow: 1.2),
);
