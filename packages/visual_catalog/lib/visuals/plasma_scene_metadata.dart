import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'plasma_scene',
  name: 'Campo de Plasma',
  description: 'Interferencia fluida de ondas de plasma en color puro con pulsos armónicos y reactividad espectral.',
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  purposes: ['party', 'visualizer', 'relax'],
  moods: ['hypnotic', 'energetic', 'trippy'],
  concepts: ['plasma', 'waves', 'electric'],
  credits: CreatorCredits(author: 'Color Lights Team'),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.0),
  colors: [0xff00131f, 0xff00c2b2, 0xffffd93d, 0xffff2fb9],
  controls: CreatorControls(intensity: 1.0, speed: 0.8, detail: 1.0, glow: 1.0),
);
