import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'v04_tunel_warp',
  name: 'Túnel Hiperdimensional',
  publication: CreatorPublication.draft,
  description: 'Túnel infinito octagonal de velocidad warp con perspectiva relativista, vigas de torsión longitudinales y singularidad focal.',
  purposes: ['warp', 'visualizer', 'gaming'],
  moods: ['hypnotic', 'fast', 'futuristic'],
  concepts: ['hyperspace', 'tunnel', 'octagon', 'warp speed'],
  credits: CreatorCredits(author: 'Visuales Inmersivas', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff140026, 0xff00ffcc, 0xffbd00ff, 0xff00e5ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
