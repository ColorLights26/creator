import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'lluvia_particulas_premium',
  name: 'Lluvia de Partículas Premium',
  publication: CreatorPublication.draft,
  description:
      'Lluvia de luz de cine: gotas brillantes con estela que caen a distinta distancia, las cercanas rápidas y grandes, inclinadas por el viento. Sin fondo, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['cinematic', 'calm', 'melancholic'],
  concepts: ['rain', 'light streaks', 'falling particles', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff4f6a96, 0xffc8daff, 0xffffffff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas simuladas con física: fluidas a 30 FPS en el móvil.
  framesPerSecond: 30,
);
