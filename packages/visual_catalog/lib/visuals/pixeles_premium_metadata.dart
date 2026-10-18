import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'pixeles_premium',
  name: 'Píxeles Premium',
  publication: CreatorPublication.draft,
  description:
      'Píxeles de luz: cuadraditos nítidos con un resplandor suave que flotan, suben o caen, se encienden a escalones y parpadean como una pantalla. Sin fondo, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['digital', 'retro', 'energetic'],
  concepts: ['pixels', 'digital', 'glow', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffd1001c, 0xffff5a1f, 0xffffd60a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas simuladas con física: fluidas a 30 FPS en el móvil.
  framesPerSecond: 30,
);
