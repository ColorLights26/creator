import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'causticas',
  name: 'Cáusticas Profundas',
  publication: CreatorPublication.draft,
  description:
      'Fondo marino bajo la red de luz del oleaje: los graves agitan las cáusticas, los golpes salpican la luz y los agudos encienden el plancton.',
  purposes: ['relax', 'visualizer', 'chill'],
  moods: ['calm', 'aquatic', 'dreamy'],
  concepts: ['caustics', 'underwater', 'ocean', 'light'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff010c14, 0xff0a5d73, 0xff5ff3e8, 0xfffff0c8],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
