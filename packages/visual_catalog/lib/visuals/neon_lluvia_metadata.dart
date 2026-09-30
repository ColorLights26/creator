import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'neon_lluvia',
  name: 'Neón bajo la Lluvia',
  publication: CreatorPublication.draft,
  description: 'Ciudad de neón en cuatro capas con ventanas encendidas, reflejo mojado y lluvia arrastrada por el viento.',
  purposes: ['relax', 'visualizer'],
  moods: ['nocturnal', 'melancholic'],
  concepts: ['city', 'rain', 'neon'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff05060c, 0xffff6a55, 0xff131a2c, 0xffbed7ff],
  controls: CreatorControls(intensity: 1, speed: .7, detail: 1, glow: .8),
);
