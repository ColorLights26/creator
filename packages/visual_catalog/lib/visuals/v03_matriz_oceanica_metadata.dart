import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'v03_matriz_oceanica',
  name: 'Matriz Oceánica 3D',
  publication: CreatorPublication.draft,
  description: 'Malla tridimensional retrowave con oleaje armónico multi-frecuencia, sol synthwave con persianas y niebla de profundidad.',
  purposes: ['retrowave', 'visualizer', 'driving'],
  moods: ['cyberpunk', 'nostalgic', 'energetic'],
  concepts: ['synthwave', 'ocean grid', 'wireframe', 'sun'],
  credits: CreatorCredits(author: 'Visuales Inmersivas', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff070014, 0xff00fff2, 0xffff007f, 0xffff7700],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
