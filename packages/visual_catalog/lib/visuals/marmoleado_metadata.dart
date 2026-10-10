import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'marmoleado',
  name: 'Marmoleado',
  publication: CreatorPublication.draft,
  description:
      'Arte ebru en vivo: gotas de tinta carmesí, amarilla, azul y blanca se abren en anillos sobre el agua y un peine las arrastra en plumas y remolinos con cada golpe.',
  purposes: ['visualizer', 'relax', 'focus'],
  moods: ['satisfying', 'artistic', 'vivid'],
  concepts: ['paper marbling', 'ebru', 'ink', 'combing'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 12),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff07070c, 0xffd7102a, 0xffffd400, 0xff1240ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las gotas se abren y el peine se mueve con suavidad: a 60 FPS es fluido.
  framesPerSecond: 30,
);
