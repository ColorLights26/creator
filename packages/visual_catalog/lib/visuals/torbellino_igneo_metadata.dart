import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'torbellino_igneo',
  name: 'Torbellino Ígneo',
  publication: CreatorPublication.draft,
  description:
      'Torbellino de estelas de luz naranja que giran en espiral hacia un núcleo incandescente y estallan hacia fuera con cada golpe.',
  purposes: ['party', 'visualizer', 'relax'],
  moods: ['epic', 'hypnotic', 'warm'],
  concepts: ['particles', 'vortex', 'trails', 'spiral'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff050200, 0xffd9300a, 0xffff6a00, 0xffffa22a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Giro continuo de estelas: a 60 FPS el remolino es fluido.
  framesPerSecond: 60,
);
