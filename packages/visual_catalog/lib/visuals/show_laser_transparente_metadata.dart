import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'show_laser_transparente',
  name: 'Show Láser Transparente',
  publication: CreatorPublication.draft,
  description:
      'Espectáculo de láseres de festival: abanicos de rayos de colores que barren el humo, se abren y destellan con cada golpe sobre fondo transparente.',
  purposes: ['party', 'visualizer'],
  moods: ['epic', 'energetic', 'club'],
  concepts: ['lasers', 'beams', 'festival', 'light show'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffff1e5a, 0xff2bff6a, 0xff1ec8ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
