import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'v05_campo_curl_transparente',
  name: 'Campo de Flujo Vectorial Transparente',
  publication: CreatorPublication.draft,
  description: 'Cintas bioluminiscentes guiadas por un campo analítico de rotacional curl noise sobre fondo transparente.',
  purposes: ['fluid', 'visualizer', 'relax'],
  moods: ['smooth', 'hypnotic', 'organic'],
  concepts: ['curl noise', 'vector field', 'particles', 'flow'],
  credits: CreatorCredits(author: 'Visuales Inmersivas', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff00ffa6, 0xff4cc9f0, 0xfff72585],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
