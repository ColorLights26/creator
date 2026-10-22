import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'rayos_polvo_dorado',
  name: 'Rayos de Luz con Polvo Dorado',
  publication: CreatorPublication.draft,
  description:
      'Haces de luz dorada que entran en diagonal y polvo de oro que flota en el aire: fuera de la luz casi no se ve y, al cruzar un haz, brilla y destella. Sin fondo, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['cinematic', 'dreamy', 'elegant'],
  concepts: ['god rays', 'golden dust', 'light beams', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffa0520a, 0xffffaa33, 0xfffff2cc],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas simuladas con física: fluidas a 30 FPS en el móvil.
  framesPerSecond: 30,
);
