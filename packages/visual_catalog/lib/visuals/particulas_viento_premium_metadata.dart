import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'particulas_viento_premium',
  name: 'Partículas al Viento Premium',
  publication: CreatorPublication.draft,
  description:
      'Partículas de luz que cruzan la pantalla llevadas por el viento, ondulando, con núcleo brillante y estela que se apaga, a distinta distancia. Sin fondo, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['dynamic', 'elegant', 'cinematic'],
  concepts: ['wind', 'light trails', 'drifting particles', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff8a0020, 0xffff2d55, 0xffffc0cb],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas simuladas con física: fluidas a 30 FPS en el móvil.
  framesPerSecond: 30,
);
