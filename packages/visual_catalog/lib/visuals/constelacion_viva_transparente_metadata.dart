import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'constelacion_viva_transparente',
  name: 'Constelación Táctil Transparente',
  publication: CreatorPublication.draft,
  description:
      'Constelación 3D de estrellas luminosas unidas por líneas de luz con pulsos de energía; estalla y se expande con cada golpe sobre fondo transparente.',
  purposes: ['party', 'relax', 'visualizer'],
  moods: ['cosmic', 'epic', 'dreamy'],
  concepts: ['constellation', 'stars', 'network', 'energy'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff2ee6ff, 0xffff3df2, 0xffffe9b0],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
