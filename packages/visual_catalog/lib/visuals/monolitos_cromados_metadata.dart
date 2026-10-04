import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'monolitos_cromados',
  name: 'Monolitos Cromados',
  publication: CreatorPublication.draft,
  description:
      'Bloques gigantes de cromo flotan en el vacío y reflejan luces de neón rojo y blanco; se separan con cada golpe y sus bordes arden con los graves.',
  purposes: ['visualizer', 'party', 'club'],
  moods: ['epic', 'futuristic', 'monumental'],
  concepts: ['chrome', 'monoliths', 'neon', 'raymarching'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff000000, 0xffff1a2e, 0xffffffff, 0xffc9d3e0],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Cámara y bloques en movimiento continuo: a 60 FPS es fluido.
  framesPerSecond: 60,
);
