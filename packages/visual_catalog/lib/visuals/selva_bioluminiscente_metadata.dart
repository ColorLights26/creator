import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'selva_bioluminiscente',
  name: 'Selva Bioluminiscente',
  publication: CreatorPublication.draft,
  description: 'Fractal verde luminoso que respira, con esporas flotando y puntas brillantes.',
  purposes: ['relax', 'visualizer'],
  moods: ['calm', 'magical'],
  concepts: ['tree', 'fractal', 'glow'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff021410, 0xff14855a, 0xff7bffb0, 0xffffffff],
  controls: CreatorControls(intensity: 1, speed: .6, detail: 1, glow: 1),
);
