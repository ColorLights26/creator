import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'escena_demo',
  name: 'Escena Demo',
  publication: CreatorPublication.draft,
  description:
      'Los efectos míticos de las demos de Amiga y PC de los noventa: barras de cobre que ondulan, la columna retorcida, el fuego de píxeles y el suelo giratorio, alternando con la música.',
  purposes: ['visualizer', 'party', 'club'],
  moods: ['retro', 'energetic', 'nostalgic'],
  concepts: ['demoscene', 'copper bars', 'twister', 'pixel fire', 'rotozoom'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff05041a, 0xffff2a2a, 0xffffa000, 0xffffe840],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Los efectos se mueven sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
