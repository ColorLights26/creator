import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'globo_tesla',
  name: 'Globo Tesla',
  publication: CreatorPublication.draft,
  description:
      'Lámpara de plasma cuyos filamentos siguen el espectro y saltan a nuevas posiciones con cada golpe.',
  purposes: ['party', 'visualizer'],
  moods: ['electric', 'energetic', 'mysterious'],
  concepts: ['plasma globe', 'electricity', 'tesla', 'lightning'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff05030b, 0xffd64bff, 0xff4f6dff, 0xffffd6f6],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
