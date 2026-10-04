import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'ola_pendulos_transparente',
  name: 'Ola de Péndulos Transparente',
  publication: CreatorPublication.draft,
  description:
      'Una fila de péndulos de luz de largos distintos: juntos forman serpientes, ondas y patrones que se deshacen y vuelven a formarse al ritmo de la música sobre fondo transparente.',
  purposes: ['visualizer', 'focus', 'relax'],
  moods: ['hypnotic', 'warm', 'satisfying'],
  concepts: ['pendulum wave', 'physics', 'interference', 'motion'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffff1a1a, 0xffff8a00, 0xffffe040],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las bolas oscilan sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
