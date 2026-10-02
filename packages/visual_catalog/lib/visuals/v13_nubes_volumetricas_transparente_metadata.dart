import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'v13_nubes_volumetricas_transparente',
  name: 'Nubes Volumétricas Transparente',
  publication: CreatorPublication.draft,
  description: 'Raymarching 3D volumétrico de manto de nubes al atardecer sobre cielo transparente.',
  purposes: ['atmosphere', 'relax', 'visualizer'],
  moods: ['dreamy', 'epic', 'peaceful'],
  concepts: ['volumetric', 'clouds', 'raymarching', 'sunset', 'atmosphere'],
  credits: CreatorCredits(author: 'Visuales Inmersivas', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.0),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xfffff1dc, 0xffc9b7d6, 0xff241a35],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
