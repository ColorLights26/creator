import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'descarga_tesla_transparente',
  name: 'Descarga Tesla Transparente',
  publication: CreatorPublication.draft,
  description:
      'Plasma eléctrico a pantalla completa: rayos ramificados desde un núcleo de energía que siguen el espectro y estallan con cada golpe sobre fondo transparente.',
  purposes: ['party', 'visualizer'],
  moods: ['electric', 'energetic', 'mysterious'],
  concepts: ['plasma', 'electricity', 'tesla', 'lightning'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffd64bff, 0xff4f6dff, 0xffffd6f6],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
