import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'nebulosa_viva',
  name: 'Nebulosa Viva',
  publication: CreatorPublication.draft,
  description:
      'Nebulosa volumétrica iluminada desde dentro: cada golpe enciende su estrella y lanza una onda de choque a través del gas.',
  purposes: ['relax', 'visualizer', 'party'],
  moods: ['cosmic', 'dreamy', 'epic'],
  concepts: ['nebula', 'space', 'gas', 'stars'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff02030a, 0xffd23cff, 0xff2fa8ff, 0xffffd9a8],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
