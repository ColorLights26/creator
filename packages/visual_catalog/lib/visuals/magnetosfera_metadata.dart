import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'magnetosfera',
  name: 'Magnetosfera',
  publication: CreatorPublication.draft,
  description:
      'Núcleos de energía naranja y azul rodeados de miles de partículas en órbita que estallan como supernovas con cada golpe.',
  purposes: ['visualizer', 'party', 'relax'],
  moods: ['cosmic', 'hypnotic', 'epic'],
  concepts: ['particles', 'orbits', 'magnetism', 'nebula'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff03040a, 0xffff8a2a, 0xff2a5cff, 0xffffffff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Órbitas continuas: a 60 FPS las partículas giran con fluidez.
  framesPerSecond: 30, // energía: 60 no cabe; ver energy/frame_rate_record.json
);
