import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'goteo_pollock_transparente',
  name: 'Goteo Pollock Transparente',
  publication: CreatorPublication.draft,
  description:
      'Un cuadro de Jackson Pollock que se pinta solo: latigazos de pintura negra, roja, amarilla y blanca, charcos y salpicaduras que caen con cada golpe de la música hasta llenar el lienzo sobre fondo transparente.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['artistic', 'chaotic', 'bold'],
  concepts: ['action painting', 'pollock', 'drip painting', 'abstract expressionism'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 12),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffd8141e, 0xffffbf00, 0xff121212],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Los chorros de pintura se dibujan mientras vuelan: a 60 FPS es fluido.
  framesPerSecond: 30,
);
