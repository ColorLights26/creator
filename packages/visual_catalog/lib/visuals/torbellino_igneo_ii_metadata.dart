import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'torbellino_igneo_ii',
  name: 'Torbellino Ígneo II',
  publication: CreatorPublication.draft,
  description:
      'Torbellino de fuego líquido: corrientes incandescentes que giran en espiral hacia un núcleo ardiente, con chispas y una onda de choque en cada golpe.',
  purposes: ['party', 'visualizer', 'relax'],
  moods: ['epic', 'hypnotic', 'warm'],
  concepts: ['vortex', 'fire', 'spiral', 'fluid'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff050200, 0xffc8280a, 0xffff6a00, 0xffffa22a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Giro continuo del fuego: a 60 FPS el remolino es fluido.
  framesPerSecond: 30, // energía: 60 no cabe; ver energy/frame_rate_record.json
);
