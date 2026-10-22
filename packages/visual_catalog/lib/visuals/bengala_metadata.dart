import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'bengala',
  name: 'Bengala',
  publication: CreatorPublication.draft,
  description:
      'Bengalas que dibujan en el aire: dejan un trazo de luz que se apaga despacio, como en una foto de larga exposición, y su punta escupe chispas que se parten en dos al volar. Sin fondo, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['festive', 'magical', 'warm'],
  concepts: ['sparkler', 'light painting', 'sparks', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffe0420a, 0xffffa000, 0xfffffbe8],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas simuladas con física: fluidas a 30 FPS en el móvil.
  framesPerSecond: 30,
);
