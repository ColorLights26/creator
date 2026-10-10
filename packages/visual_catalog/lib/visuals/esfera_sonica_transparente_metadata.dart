import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'esfera_sonica_transparente',
  name: 'Esfera Sónica Transparente',
  publication: CreatorPublication.draft,
  description:
      'Esfera 3D de miles de puntos de luz verde que se deforma con el espectro y explota en una nube en el drop antes de volver a formarse sobre fondo transparente.',
  purposes: ['party', 'visualizer', 'club'],
  moods: ['epic', 'futuristic', 'energetic'],
  concepts: ['particles', 'sphere', '3d', 'spectrum'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff00ff6a, 0xffb4ff00, 0xffffffff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Giro continuo en 3D: a 60 FPS la esfera gira con fluidez.
  framesPerSecond: 30,
);
