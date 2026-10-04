import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'mancha_rorschach',
  name: 'Mancha de Rorschach',
  publication: CreatorPublication.draft,
  description:
      'Una mancha de tinta negra y roja perfectamente simétrica sobre papel crema que respira, se transforma y salpica con la música, como las láminas del test de Rorschach.',
  purposes: ['visualizer', 'focus', 'relax'],
  moods: ['artistic', 'mysterious', 'bold'],
  concepts: ['rorschach', 'inkblot', 'symmetry', 'ink'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xfff1e6cf, 0xff0a0505, 0xffc8001e, 0xff5a0010],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta se transforma despacio y salpica rápido: a 60 FPS es fluido.
  framesPerSecond: 60,
);
