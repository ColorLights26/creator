import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'v13_nubes_volumetricas',
  name: 'Nubes Volumétricas',
  publication: CreatorPublication.draft,
  description: 'Raymarching 3D volumétrico de manto de nubes al atardecer, absorción de Beer-Lambert, paleta dorada y relámpagos de exposición reactivos.',
  purposes: ['atmosphere', 'relax', 'visualizer'],
  moods: ['dreamy', 'epic', 'peaceful'],
  concepts: ['volumetric', 'clouds', 'raymarching', 'sunset', 'atmosphere'],
  credits: CreatorCredits(author: 'Visuales Inmersivas', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.0),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff0d1024, 0xfffff1dc, 0xffc9b7d6, 0xff241a35],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
