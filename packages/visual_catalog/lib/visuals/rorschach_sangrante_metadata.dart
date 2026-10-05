import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'rorschach_sangrante',
  name: 'Rorschach Sangrante',
  publication: CreatorPublication.draft,
  description:
      'Una mancha de Rorschach de sangre brillante que cambia de forma con cada golpe, chupa el papel por sus fibras y suelta regueros que bajan; los golpes la hacen latir y salpicar.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['disturbing', 'organic', 'intense'],
  concepts: ['rorschach', 'blood', 'dripping', 'inkblot'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 4),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xffe8dcc4, 0xff3a0003, 0xffb8000e, 0xffff2a2a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta cambia de forma sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
