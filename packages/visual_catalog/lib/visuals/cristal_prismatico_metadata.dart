import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'cristal_prismatico',
  name: 'Cristal Prismático',
  publication: CreatorPublication.draft,
  description:
      'Gema cuántica hiperfacetada con dispersión óptica arcoíris, refracción interna y caústicas que estallan al ritmo de la música.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['radiant', 'luxurious', 'kaleidoscopic'],
  concepts: ['crystal', 'gem', 'refraction', 'rainbow', 'prismatic', 'diamond'],
  credits: CreatorCredits(
    author: 'Color Lights 26',
    license: 'Proprietary',
    source: 'Color Lights Studio',
  ),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3.0),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xFF050512, 0xFF38E1FF, 0xFFF33D98, 0xFFFFDF00],
  controls: CreatorControls(intensity: 1.0, speed: 1.0, detail: 1.0, glow: 1.2),
);
