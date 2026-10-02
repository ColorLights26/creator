import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'descarga_tesla',
  name: 'Descarga Tesla',
  publication: CreatorPublication.draft,
  description:
      'Plasma eléctrico a pantalla completa: rayos ramificados desde un núcleo de energía que siguen el espectro y estallan con cada golpe.',
  purposes: ['party', 'visualizer'],
  moods: ['electric', 'energetic', 'mysterious'],
  concepts: ['plasma', 'electricity', 'tesla', 'lightning'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff05030b, 0xffd64bff, 0xff4f6dff, 0xffffd6f6],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
