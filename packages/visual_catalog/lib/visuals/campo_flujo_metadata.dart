import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'campo_flujo',
  name: 'Campo de Flujo',
  publication: CreatorPublication.draft,
  description: 'Mil cuatrocientas partículas siguiendo un campo de flujo sinusoidal, con estelas y remolino central.',
  purposes: ['relax', 'visualizer'],
  moods: ['fluid', 'calm'],
  concepts: ['particles', 'flow field', 'trails'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff05090c, 0xff3fd8a5, 0xffc6e84f, 0xff58c7f3],
  controls: CreatorControls(intensity: 1, speed: .6, detail: 1, glow: .8),
);
