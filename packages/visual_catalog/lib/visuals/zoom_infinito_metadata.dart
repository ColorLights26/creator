import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'zoom_infinito',
  name: 'Zoom Infinito',
  publication: CreatorPublication.draft,
  description:
      'Viaje sin fin hacia dentro del fractal de Mandelbrot con colores de fuego: espirales que aparecen sin parar y laten con la música.',
  purposes: ['visualizer', 'relax', 'party'],
  moods: ['hypnotic', 'epic', 'psychedelic'],
  concepts: ['mandelbrot', 'fractal', 'zoom', 'infinity'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3.0),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff000000, 0xffb30000, 0xffff6a00, 0xffffe066],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Zoom continuo: a 60 FPS el viaje es fluido.
  framesPerSecond: 60,
);
