import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'brasas_premium',
  name: 'Brasas Premium',
  publication: CreatorPublication.draft,
  description:
      'Brasas de fuego de cine: chispas con núcleo caliente y estela naranja que suben desde un resplandor de fuego, se enroscan en el aire caliente y se apagan; las cercanas, grandes y desenfocadas. Sin fondo, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['cinematic', 'warm', 'epic'],
  concepts: ['embers', 'fire', 'sparks', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffb3140a, 0xffff6a0a, 0xffffd27a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas simuladas con física: fluidas a 30 FPS en el móvil.
  framesPerSecond: 30,
);
