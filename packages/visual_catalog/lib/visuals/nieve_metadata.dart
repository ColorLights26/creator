import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'nieve',
  name: 'Nieve',
  publication: CreatorPublication.draft,
  description:
      'Capa transparente de nieve: copos blancos suaves que caen despacio meciéndose, los cercanos más grandes y desenfocados, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['calm', 'dreamy', 'cozy'],
  concepts: ['snow', 'falling particles', 'winter', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff9fb4d6, 0xffe8f0ff, 0xffffffff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas sencillas: a 30 FPS gastan poca batería.
  framesPerSecond: 30,
);
