import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'tunel_laser',
  name: 'Túnel Láser Arcoíris',
  publication: CreatorPublication.draft,
  description:
      'Túnel de paneles dorados encendidos con marcos de neón arcoíris girados y láseres amarillos, magenta, cian y verdes que barren la pantalla.',
  purposes: ['party', 'club', 'visualizer'],
  moods: ['festive', 'energetic', 'colorful'],
  concepts: ['tunnel', 'lasers', 'rainbow', 'led panels'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff020100, 0xffffb000, 0xffff2bd6, 0xff2bffd0],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Avance continuo y láseres en movimiento: a 60 FPS es fluido.
  framesPerSecond: 60,
);
