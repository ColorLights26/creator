import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'ferrofluido',
  name: 'Ferrofluido',
  publication: CreatorPublication.draft,
  description:
      'Charco de líquido magnético negro cuyas púas se levantan con los graves y el espectro bajo luz de estudio.',
  purposes: ['party', 'visualizer'],
  moods: ['dark', 'glossy', 'energetic'],
  concepts: ['ferrofluid', 'liquid', 'magnetic', 'spikes'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff040308, 0xffff2e88, 0xff21d4fd, 0xfffff1e0],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
