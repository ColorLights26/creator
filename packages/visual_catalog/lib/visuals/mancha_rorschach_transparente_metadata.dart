import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'mancha_rorschach_transparente',
  name: 'Mancha de Rorschach Transparente',
  publication: CreatorPublication.draft,
  description:
      'Una mancha de tinta negra y roja perfectamente simétrica sobre papel crema que respira, se transforma y salpica con la música, como las láminas del test de Rorschach sobre fondo transparente.',
  purposes: ['visualizer', 'focus', 'relax'],
  moods: ['artistic', 'mysterious', 'bold'],
  concepts: ['rorschach', 'inkblot', 'symmetry', 'ink'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff0a0505, 0xffc8001e, 0xff5a0010],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta se transforma despacio y salpica rápido: a 60 FPS es fluido.
  framesPerSecond: 30,
);
