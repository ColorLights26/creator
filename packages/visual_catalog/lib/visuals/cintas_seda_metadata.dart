import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'cintas_seda',
  name: 'Cintas de Seda',
  publication: CreatorPublication.draft,
  description: 'Siete curvas de Lissajous convertidas en cintas rellenas con degradado y bordes luminosos.',
  purposes: ['relax', 'visualizer'],
  moods: ['silky', 'dreamy'],
  concepts: ['ribbons', 'lissajous', 'gradient'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff090510, 0xfff27bb6, 0xffa68bff, 0xffece6da],
  controls: CreatorControls(intensity: 1, speed: .6, detail: 1, glow: .8),
);
