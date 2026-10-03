import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'olas_cubos',
  name: 'Olas de Cubos',
  publication: CreatorPublication.draft,
  description:
      'Tablero isométrico de cubos de marfil y coral que suben y bajan en ondas hipnóticas; cada golpe lanza una ola desde el centro.',
  purposes: ['visualizer', 'focus', 'party'],
  moods: ['hypnotic', 'clean', 'modern'],
  concepts: ['isometric', 'cubes', 'waves', 'geometry'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff0b2e3a, 0xffff6f59, 0xfff4ead8, 0xff06202a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Ondas continuas: a 60 FPS los cubos se mueven con fluidez.
  framesPerSecond: 60,
);
