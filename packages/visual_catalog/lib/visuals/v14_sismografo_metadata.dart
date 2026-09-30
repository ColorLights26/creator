import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'v14_sismografo',
  name: 'Sismógrafo',
  publication: CreatorPublication.draft,
  description: 'Tambor sismográfico de metal cepillado con reflejo anisotrópico, aguja mecánica visible y trazo fosforescente cian de ondas sísmicas reactivas.',
  purposes: ['scientific', 'visualizer', 'retro'],
  moods: ['analytical', 'tense', 'technical'],
  concepts: ['seismograph', 'earthquake', 'oscilloscope', 'drum', 'needle', 'laboratory'],
  credits: CreatorCredits(author: 'Visuales Inmersivas', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.0),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff0b0d10, 0xff2a2d33, 0xff7df9ff, 0xffc8d0dc],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
