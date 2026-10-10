import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'capas_papel',
  name: 'Capas de Papel',
  publication: CreatorPublication.draft,
  description:
      'Paisaje abstracto de papel recortado en capas magenta, naranja y amarillo con sombras y profundidad; cada capa ondula con su banda de la música.',
  purposes: ['visualizer', 'relax', 'party'],
  moods: ['crafty', 'warm', 'dreamy'],
  concepts: ['paper cut', 'parallax', 'layers', 'landscape'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff1a0020, 0xffff2d95, 0xffff7a1a, 0xffffd400],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Capas que se desplazan sin parar: a 60 FPS es fluido.
  framesPerSecond: 30,
);
