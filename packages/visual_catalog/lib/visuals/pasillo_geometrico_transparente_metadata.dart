import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'pasillo_geometrico_transparente',
  name: 'Pasillo Geométrico Transparente',
  publication: CreatorPublication.draft,
  description:
      'Triángulos, rombos, cruces y estrellas de neón rojo y blanco que nacen en el centro y crecen hacia ti con cada golpe, con ráfagas de picos sobre fondo transparente.',
  purposes: ['party', 'club', 'visualizer'],
  moods: ['intense', 'bold', 'futuristic'],
  concepts: ['geometric', 'neon shapes', 'zoom', 'vj loop'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.0),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffff1a1a, 0xffffffff, 0xff3d7bff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Formas que crecen sin parar: a 60 FPS el zoom es fluido.
  framesPerSecond: 60,
);
