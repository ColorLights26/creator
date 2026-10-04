import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'mandala_alucinante_transparente',
  name: 'Mandala Alucinante Transparente',
  publication: CreatorPublication.draft,
  description:
      'Mandala fractal ornamentado que se transforma sin parar con colores psicodélicos que circulan; respira con los graves y cambia de simetría con los golpes sobre fondo transparente.',
  purposes: ['visualizer', 'party', 'psychedelic'],
  moods: ['psychedelic', 'hypnotic', 'mystic'],
  concepts: ['fractal', 'mandala', 'kaleidoscope', 'psychedelic art'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3.0),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffff1e56, 0xffffb300, 0xff00d4ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // El fractal se transforma sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
