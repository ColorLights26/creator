import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'ciber_reticula',
  name: 'Ciber Retícula 3D',
  publication: CreatorPublication.draft,
  description:
      'Paisaje cyberpunk infinito en perspectiva 3D con topografía láser, sol sintetizador en el horizonte y ondas de choque.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['retro_future', 'cyberpunk', 'energetic'],
  concepts: ['cyber_grid', 'synthwave', 'perspective', 'laser', 'neon_highway'],
  credits: CreatorCredits(
    author: 'Color Lights 26',
    license: 'Proprietary',
    source: 'Color Lights Studio',
  ),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.0),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xFF050518, 0xFFF33D98, 0xFF38E1FF, 0xFFFFDF00],
  controls: CreatorControls(intensity: 1.0, speed: 1.0, detail: 1.0, glow: 1.1),
);
