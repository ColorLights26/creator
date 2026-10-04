import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'cubo_led',
  name: 'Cubo LED 3D',
  publication: CreatorPublication.draft,
  description:
      'Un cubo de 8×8×8 luces que gira en el espacio: lluvia, ondas, el espectro de la música en volumen, explosiones y espirales encendidas en rojo, naranja y amarillo.',
  purposes: ['visualizer', 'party', 'club'],
  moods: ['tech', 'energetic', 'retro'],
  concepts: ['led cube', '3d', 'voxels', 'maker'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff040306, 0xffff1a2a, 0xffff8a00, 0xffffe640],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // El cubo gira y sus luces cambian sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
