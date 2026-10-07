import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'tuberias_3d',
  name: 'Tuberías 3D',
  publication: CreatorPublication.draft,
  description:
      'El salvapantallas clásico de tuberías en 3D, rehecho con brillo: tubos rojos, amarillos y azules que crecen, giran en codos y llenan el espacio al ritmo de la música.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['retro', 'playful', 'satisfying'],
  concepts: ['3d pipes', 'screensaver', 'growth', 'retro computing'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 6),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff04050b, 0xffff2020, 0xffffc400, 0xff2b5cff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Los tubos crecen de forma continua: a 60 FPS es fluido.
  framesPerSecond: 30, // energía: ver energy/frame_rate_record.json
);
