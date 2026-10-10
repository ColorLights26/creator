import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'cubo_magico',
  name: 'Cubo Mágico',
  publication: CreatorPublication.draft,
  description:
      'Un cubo de colores de 3×3 que gira en 3D, se desordena capa a capa al ritmo de la música y luego se resuelve solo, con un destello al quedar perfecto.',
  purposes: ['visualizer', 'focus', 'party'],
  moods: ['satisfying', 'playful', 'vivid'],
  concepts: ['puzzle cube', '3d', 'scramble', 'solve'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff07060c, 0xffff2a1a, 0xffff9500, 0xffffe14a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las capas giran con suavidad: a 60 FPS es fluido.
  framesPerSecond: 30,
);
