import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'curvas_fractales',
  name: 'Curvas Fractales',
  publication: CreatorPublication.draft,
  description:
      'Una sola línea de luz que llena la pantalla plegándose en curvas fractales cada vez más finas (Hilbert, dragón, Gosper y Koch) mientras un pulso de color la recorre con la música.',
  purposes: ['visualizer', 'focus', 'relax'],
  moods: ['mathematical', 'hypnotic', 'elegant'],
  concepts: ['space-filling curve', 'hilbert curve', 'dragon curve', 'l-system'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff040208, 0xffff1a4a, 0xffff8a00, 0xffffe050],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La línea se dibuja de forma continua: a 60 FPS es fluido.
  framesPerSecond: 60,
);
