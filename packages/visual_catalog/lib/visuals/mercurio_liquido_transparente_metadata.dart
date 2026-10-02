import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'mercurio_liquido_transparente',
  name: 'Mercurio Líquido Transparente',
  publication: CreatorPublication.draft,
  description:
      'Cromo fundido y mercurio líquido hiperreflectivo con ondas concéntricas y brillos sobre fondo transparente.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['sleek', 'futuristic', 'metallic'],
  concepts: ['chrome', 'mercury', 'liquid_metal', 'reflections', 'futuristic'],
  credits: CreatorCredits(
    author: 'Color Lights 26',
    license: 'Proprietary',
    source: 'Color Lights Studio',
  ),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.0),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xFF88AACC, 0xFFFFFFFF, 0xFF38E1FF],
  controls: CreatorControls(intensity: 1.0, speed: 1.0, detail: 1.0, glow: 1.0),
);
