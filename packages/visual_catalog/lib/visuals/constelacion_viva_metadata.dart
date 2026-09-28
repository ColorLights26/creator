import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'constelacion_viva',
  name: 'Constelación Táctil',
  publication: CreatorPublication.draft,
  description: 'Grafo de vecindad con rejilla espacial: los nodos se repelen del centro y las aristas brillan por cercanía.',
  purposes: ['relax', 'visualizer'],
  moods: ['dreamy', 'calm'],
  concepts: ['graph', 'nodes', 'network'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff120f24, 0xffa68bff, 0xffcbb8ff, 0xff080710],
  controls: CreatorControls(intensity: 1, speed: .6, detail: 1, glow: .8),
);
