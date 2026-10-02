import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'metal_tornasol',
  name: 'Metal Tornasol',
  publication: CreatorPublication.draft,
  description:
      'Metal líquido con reflejos tornasolados vivos que estalla en ondas de choque y cambia de tono con cada golpe.',
  purposes: ['party', 'visualizer'],
  moods: ['energetic', 'glossy', 'epic'],
  concepts: ['liquid metal', 'iridescence', 'chrome', 'shockwave'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff05030b, 0xffff1fc8, 0xff00e1ff, 0xffffc800],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
