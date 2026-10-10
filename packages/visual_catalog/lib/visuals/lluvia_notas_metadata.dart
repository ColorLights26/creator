import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'lluvia_notas',
  name: 'Lluvia de Notas',
  publication: CreatorPublication.draft,
  description:
      'Como los vídeos de piano con notas de colores: barras de neón rojas, naranjas y amarillas brotan de un teclado de luz al ritmo de la música y suben hasta perderse arriba.',
  purposes: ['visualizer', 'relax', 'party'],
  moods: ['musical', 'warm', 'elegant'],
  concepts: ['piano roll', 'synthesia', 'notes', 'keyboard'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 6),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff06030a, 0xffff2244, 0xffff8800, 0xffffdd33],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las notas suben de forma continua: a 60 FPS es fluido.
  framesPerSecond: 30,
);
