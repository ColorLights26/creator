import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'cristales_polarizados',
  name: 'Cristales Polarizados',
  publication: CreatorPublication.draft,
  description:
      'Cristales que crecen como flores bajo luz polarizada, con colores de interferencia intensos y cruces oscuras que giran con la música.',
  purposes: ['visualizer', 'relax', 'party'],
  moods: ['hypnotic', 'vivid', 'scientific'],
  concepts: ['crystals', 'polarized light', 'microscope', 'growth'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 4.0),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff000000, 0xffffb02e, 0xff19e0c8, 0xffff3fa4],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Crecimiento y giro de la luz continuos: a 60 FPS es fluido.
  framesPerSecond: 30, // energía: 60 no cabe; ver energy/frame_rate_record.json
);
