import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'telar',
  name: 'Telar',
  publication: CreatorPublication.draft,
  description:
      'Un telar teje sin parar una tela de colores andinos: hilos rojos, naranjas, amarillos, fucsias y turquesa que se cruzan en tafetán, sarga, rombos y espiga mientras la lanzadera vuela con la música.',
  purposes: ['visualizer', 'relax', 'focus'],
  moods: ['crafty', 'warm', 'hypnotic'],
  concepts: ['weaving', 'loom', 'textile', 'pattern'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff120806, 0xffe0102a, 0xffff7a00, 0xffffc81e],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tela sube de forma continua: a 60 FPS es fluido.
  framesPerSecond: 60,
);
