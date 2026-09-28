import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'salto_hiperespacial',
  name: 'Salto Hiperespacial',
  publication: CreatorPublication.draft,
  description: 'Túnel de aros hexagonales y octogonales con 260 estelas estelares que se aceleran con los graves.',
  purposes: ['party', 'visualizer'],
  moods: ['hypnotic', 'cosmic'],
  concepts: ['tunnel', 'warp', 'rings'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff04060d, 0xff58c7f3, 0xffa68bff, 0xffdce9ff],
  controls: CreatorControls(intensity: 1, speed: .8, detail: 1, glow: .9),
);
