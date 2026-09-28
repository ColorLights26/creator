import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'corona_solar',
  name: 'Corona Solar',
  publication: CreatorPublication.draft,
  description: 'Limbo solar deformado por siete armónicos, con filamentos de corona y gránulos de plasma.',
  purposes: ['party', 'visualizer'],
  moods: ['fiery', 'energetic'],
  concepts: ['sun', 'corona', 'plasma'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff1b0d05, 0xfff5a524, 0xff6a55, 0xfffff6d8],
  controls: CreatorControls(intensity: 1, speed: .6, detail: 1, glow: .9),
);
