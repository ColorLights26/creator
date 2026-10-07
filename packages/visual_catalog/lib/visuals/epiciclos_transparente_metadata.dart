import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'epiciclos_transparente',
  name: 'Epiciclos Transparente',
  publication: CreatorPublication.draft,
  description:
      'Círculos que giran dentro de círculos dibujando con un lápiz de luz figuras que cambian con la música: el tamaño de cada círculo lo marca su banda del espectro sobre fondo transparente.',
  purposes: ['visualizer', 'focus', 'relax'],
  moods: ['mathematical', 'hypnotic', 'elegant'],
  concepts: ['fourier series', 'epicycles', 'drawing', 'harmonics'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 4),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffff5a00, 0xffa8ff00, 0xfffff4e0],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Los círculos giran sin parar: a 60 FPS es fluido.
  framesPerSecond: 30, // energía: 60 no cabe; ver energy/frame_rate_record.json
);
