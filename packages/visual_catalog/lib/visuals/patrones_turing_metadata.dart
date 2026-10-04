import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'patrones_turing',
  name: 'Patrones de Turing',
  publication: CreatorPublication.draft,
  description:
      'Manchas de naranja neón que crecen y se transforman en laberintos, rayas y corales sobre negro y turquesa; mutan con cada golpe.',
  purposes: ['visualizer', 'relax', 'party'],
  moods: ['organic', 'hypnotic', 'vivid'],
  concepts: ['reaction diffusion', 'turing patterns', 'labyrinth', 'generative'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff010506, 0xffff5e00, 0xff00c9b1, 0xffffe3a0],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Los patrones crecen sin parar: a 60 FPS la transformación es fluida.
  framesPerSecond: 60,
);
