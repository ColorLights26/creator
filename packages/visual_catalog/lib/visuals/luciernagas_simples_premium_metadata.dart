import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'luciernagas_simples_premium',
  name: 'Luciérnagas Premium',
  publication: CreatorPublication.draft,
  description:
      'Luciérnagas en la noche: lucecitas verde amarillo con un halo cálido que vagan despacio y se encienden y se apagan, algunas cerca y desenfocadas. Sin fondo, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['calm', 'magical', 'romantic'],
  concepts: ['fireflies', 'glow', 'night', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff2f5a00, 0xffaef000, 0xfff2ff9e],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas simuladas con física: fluidas a 30 FPS en el móvil.
  framesPerSecond: 30,
);
