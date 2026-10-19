import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'particulas_fuego',
  name: 'Partículas de Fuego',
  publication: CreatorPublication.draft,
  description:
      'Partículas de fuego que vuelan en diagonal con estelas de movimiento entre un humo frío, con bokeh rojo desenfocado y un resplandor cálido abajo. Sin fondo, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['cinematic', 'epic', 'intense'],
  concepts: ['fire particles', 'bokeh', 'smoke', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffb3140a, 0xffff6a0a, 0xffffd27a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas simuladas con física: fluidas a 30 FPS en el móvil.
  framesPerSecond: 30,
);
