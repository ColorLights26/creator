import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'mercurio_liquido',
  name: 'Mercurio Líquido',
  publication: CreatorPublication.draft,
  description:
      'Cromo fundido y mercurio líquido hiperreflectivo con ondas concéntricas y brillos especulares al compás del ritmo.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['sleek', 'futuristic', 'metallic'],
  concepts: ['chrome', 'mercury', 'liquid_metal', 'reflections', 'futuristic'],
  credits: CreatorCredits(
    author: 'Color Lights 26',
    license: 'Proprietary',
    source: 'Color Lights Studio',
  ),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.0),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xFF050810, 0xFF88AACC, 0xFFFFFFFF, 0xFF38E1FF],
  controls: CreatorControls(intensity: 1.0, speed: 1.0, detail: 1.0, glow: 1.0),
);
