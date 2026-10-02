import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'vortice_hipnotico_transparente',
  name: 'Vórtice Hipnótico Transparente',
  publication: CreatorPublication.draft,
  description: 'Anillos hexagonales de colores girando hacia un centro luminoso sobre fondo transparente.',
  purposes: ['party', 'visualizer'],
  moods: ['hypnotic', 'energetic'],
  concepts: ['vortex', 'rings', 'tunnel'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffff2e9a, 0xff3ef0ff, 0xffffffcc],
  controls: CreatorControls(intensity: 1, speed: .7, detail: 1, glow: .9),
);
