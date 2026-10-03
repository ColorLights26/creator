import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'llama_fractal',
  name: 'Llama Fractal',
  publication: CreatorPublication.draft,
  description:
      'Llamas fractales de seda luminosa en azul eléctrico y violeta que se pliegan en remolinos y mutan de forma con cada golpe.',
  purposes: ['party', 'visualizer', 'relax'],
  moods: ['hypnotic', 'epic', 'dreamy'],
  concepts: ['fractal flame', 'silk', 'swirl', 'generative'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff020108, 0xff1f4dff, 0xff9d2bff, 0xffe6dcff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La seda se transforma sin parar: a 60 FPS el giro es fluido.
  framesPerSecond: 60,
);
