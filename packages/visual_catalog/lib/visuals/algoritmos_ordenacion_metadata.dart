import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'algoritmos_ordenacion',
  name: 'Algoritmos de Ordenación',
  publication: CreatorPublication.draft,
  description:
      'Barras con todo el arcoíris que se desordenan y se vuelven a ordenar solas, cada vez con un algoritmo distinto (burbuja, rápido, montículo, mezcla…), al ritmo de la música.',
  purposes: ['visualizer', 'focus', 'party'],
  moods: ['satisfying', 'digital', 'vivid'],
  concepts: ['sorting algorithms', 'computer science', 'rainbow', 'bars'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 4),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff050508, 0xffff1a1a, 0xffff9500, 0xffffe600],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las barras cambian cientos de veces por segundo: a 60 FPS es fluido.
  framesPerSecond: 30, // energía: ver energy/frame_rate_record.json
);
