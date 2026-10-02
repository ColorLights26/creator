import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'mandala_fuego',
  name: 'Mandala de Fuego',
  publication: CreatorPublication.draft,
  description:
      'Mandala de líneas incandescentes sobre negro: estrellas que emanan hacia fuera, un anillo negro que estalla con cada golpe y brasas que suben.',
  purposes: ['party', 'visualizer', 'relax'],
  moods: ['epic', 'hypnotic', 'warm'],
  concepts: ['mandala', 'fire', 'sacred geometry', 'kaleidoscope'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff000000, 0xffc4260a, 0xffff6400, 0xffffb238],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Emanación continua hacia fuera: a 60 FPS el movimiento es fluido.
  framesPerSecond: 60,
);
