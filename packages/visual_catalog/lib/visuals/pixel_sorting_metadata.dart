import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'pixel_sorting',
  name: 'Pixel Sorting',
  publication: CreatorPublication.draft,
  description:
      'Arte glitch: un atardecer de colores intensos cuyos píxeles se ordenan por brillo en franjas que se derriten y gotean; cada golpe rasga la imagen y la ordena todavía más.',
  purposes: ['visualizer', 'party', 'club'],
  moods: ['glitch', 'vivid', 'edgy'],
  concepts: ['pixel sorting', 'glitch art', 'databending', 'streaks'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff12002a, 0xffff1f5a, 0xffff8c00, 0xffffe14d],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las franjas gotean sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
