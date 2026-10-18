import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'pixeles',
  name: 'Píxeles',
  publication: CreatorPublication.draft,
  description:
      'Capa transparente de píxeles: cuadraditos de luz que flotan, suben o caen y se encienden a escalones como una pantalla, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['digital', 'retro', 'energetic'],
  concepts: ['pixels', 'digital', 'particles', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffb3001b, 0xffff3b30, 0xffffd60a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas sencillas: a 30 FPS gastan poca batería.
  framesPerSecond: 30,
);
