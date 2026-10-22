import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'estallido_polvo',
  name: 'Estallido de Polvo',
  publication: CreatorPublication.draft,
  description:
      'Estallidos de polvo de colores en cámara lenta: con cada golpe, una nube de polvo finísimo rojo, naranja o amarillo sale en chorros, se frena y queda flotando. Sin fondo, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['explosive', 'festive', 'intense'],
  concepts: ['powder explosion', 'holi', 'slow motion', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffd6101e, 0xffff6400, 0xffffc800],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas simuladas con física: fluidas a 30 FPS en el móvil.
  framesPerSecond: 30,
);
