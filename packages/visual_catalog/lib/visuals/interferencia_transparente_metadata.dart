import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'interferencia_transparente',
  name: 'Interferencia Transparente',
  publication: CreatorPublication.draft,
  description:
      'Varias fuentes lanzan anillos de ondas rojas y naranjas que se cruzan y forman patrones de interferencia; cada golpe crea una fuente nueva cuyo frente se abre paso entre las demás sobre fondo transparente.',
  purposes: ['visualizer', 'focus', 'relax'],
  moods: ['hypnotic', 'scientific', 'warm'],
  concepts: ['wave interference', 'ripple tank', 'physics', 'moire'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 4),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffc80000, 0xffff7a00, 0xfffff0d0],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las ondas se mueven sin parar: a 60 FPS es fluido.
  framesPerSecond: 30,
);
