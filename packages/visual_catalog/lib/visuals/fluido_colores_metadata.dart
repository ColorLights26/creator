import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'fluido_colores',
  name: 'Fluido de Colores',
  publication: CreatorPublication.draft,
  description:
      'Simulación de fluido real: chorros de tinta roja, violeta y menta que se arremolinan y mezclan; cada golpe lanza un chorro nuevo.',
  purposes: ['party', 'visualizer', 'relax'],
  moods: ['fluid', 'vivid', 'hypnotic'],
  concepts: ['fluid simulation', 'ink', 'swirl', 'vorticity'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3.0),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff020203, 0xffff3b5c, 0xff7c4dff, 0xff00e5a0],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // El fluido se mueve sin parar: a 60 FPS los remolinos son fluidos.
  framesPerSecond: 60,
);
