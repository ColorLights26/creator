import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'flor_cosmica_transparente',
  name: 'Flor Cósmica Transparente',
  publication: CreatorPublication.draft,
  description:
      'Loto dimensional y mandala sagrado de pétalos dorados y violetas que florece en espirales de Fibonacci sobre fondo transparente.',
  purposes: ['meditation', 'visualizer', 'relax'],
  moods: ['sacred', 'hypnotic', 'spiritual', 'radiant'],
  concepts: ['mandala', 'lotus', 'fibonacci', 'sacred_geometry', 'cosmic_flower'],
  credits: CreatorCredits(
    author: 'Color Lights 26',
    license: 'Proprietary',
    source: 'Color Lights Studio',
  ),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xFFFFDF00, 0xFFF33D98, 0xFF38E1FF],
  controls: CreatorControls(intensity: 1.0, speed: 1.0, detail: 1.0, glow: 1.2),
);
