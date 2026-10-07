import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'teselado_penrose',
  name: 'Teselado de Penrose',
  publication: CreatorPublication.draft,
  description:
      'El mosaico de Penrose que nunca se repite: rombos ámbar y rojos con simetría de cinco puntas que se encienden en ondas de luz con cada golpe de la música.',
  purposes: ['visualizer', 'focus', 'relax'],
  moods: ['mathematical', 'elegant', 'warm'],
  concepts: ['penrose tiling', 'aperiodic', 'golden ratio', 'quasicrystal'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff0a0402, 0xffff9a1a, 0xffd8200a, 0xffffe9a0],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las ondas de luz se mueven sin parar: a 60 FPS es fluido.
  framesPerSecond: 30, // energía: ver energy/frame_rate_record.json
);
