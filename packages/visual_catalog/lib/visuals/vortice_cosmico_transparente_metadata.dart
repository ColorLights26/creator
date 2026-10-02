import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'vortice_cosmico_transparente',
  name: 'Vórtice Cósmico Transparente',
  publication: CreatorPublication.draft,
  description:
      'Singularidad cósmica y disco de acreción relativista con curvatura gravitacional y filamentos sobre fondo transparente.',
  purposes: ['visualizer', 'space', 'cinematic'],
  moods: ['epic', 'cosmic', 'deep'],
  concepts: ['black_hole', 'space', 'galaxy', 'singularity', 'accretion_disk'],
  credits: CreatorCredits(
    author: 'Color Lights 26',
    license: 'Proprietary',
    source: 'Color Lights Studio',
  ),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xFFFF7722, 0xFF38E1FF, 0xFFFFFFFF],
  controls: CreatorControls(intensity: 1.0, speed: 1.0, detail: 1.0, glow: 1.2),
);
