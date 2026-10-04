import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'v09_espiral_aurea_transparente',
  name: 'Espiral Áurea Sagrada Transparente',
  publication: CreatorPublication.draft,
  description: 'Espiral de Fibonacci y filotaxis sagrada de 750 nodos con gradiente espectral continuo y singularidad central sobre fondo transparente.',
  purposes: ['geometry', 'visualizer', 'meditation'],
  moods: ['sacred', 'calm', 'hypnotic'],
  concepts: ['fibonacci', 'golden spiral', 'phyllotaxis', 'sacred geometry'],
  credits: CreatorCredits(author: 'Visuales Inmersivas', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff00ffd5, 0xffffd700, 0xff9d4edd],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
