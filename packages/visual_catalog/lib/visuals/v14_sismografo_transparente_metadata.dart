import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'v14_sismografo_transparente',
  name: 'Sismógrafo Transparente',
  publication: CreatorPublication.draft,
  description: 'Trazo sismográfico analítico transparente con cuadrícula milimétrica flotante y aguja reactiva al bajo.',
  purposes: ['hud', 'visualizer'],
  moods: ['tech', 'analytical'],
  concepts: ['seismograph', 'oscillator', 'neon'],
  credits: CreatorCredits(author: 'Visuales Inmersivas'),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0xff00ffe0, 0xff00ff66, 0xffffffff, 0xff004433],
  controls: CreatorControls(intensity: 1.0, speed: 1.0, detail: 1.0, glow: 1.0),
);
