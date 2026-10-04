import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'pop_art',
  name: 'Pop Art',
  publication: CreatorPublication.draft,
  description:
      'Cómic de Lichtenstein en movimiento: tramas de puntos rojos sobre amarillo que laten con la música, estallidos de cómic en cada golpe, líneas cinéticas y paneles al estilo Warhol.',
  purposes: ['visualizer', 'party'],
  moods: ['bold', 'playful', 'energetic'],
  concepts: ['pop art', 'halftone', 'comic', 'warhol', 'lichtenstein'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xffffe600, 0xffff1e1e, 0xff00c3ff, 0xff101010],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Tramas y estallidos con golpes rápidos: a 60 FPS es fluido.
  framesPerSecond: 60,
);
