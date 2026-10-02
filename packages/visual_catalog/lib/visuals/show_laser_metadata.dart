import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'show_laser',
  name: 'Show Láser',
  publication: CreatorPublication.draft,
  description:
      'Espectáculo de láseres de festival: abanicos de rayos de colores que barren el humo, se abren y destellan con cada golpe.',
  purposes: ['party', 'visualizer'],
  moods: ['epic', 'energetic', 'club'],
  concepts: ['lasers', 'beams', 'festival', 'light show'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff020208, 0xffff1e5a, 0xff2bff6a, 0xff1ec8ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
