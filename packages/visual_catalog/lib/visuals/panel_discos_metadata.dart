import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'panel_discos',
  name: 'Panel de Discos',
  publication: CreatorPublication.draft,
  description:
      'Un panel de miles de discos amarillos y negros que se voltean en olas y forman ondas, barras del espectro, rayos y espirales al ritmo de la música, como las obras de arte cinético.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['kinetic', 'graphic', 'satisfying'],
  concepts: ['flip-disc', 'flip-dot', 'kinetic art', 'display'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff121212, 0xffffd400, 0xff1c1c1c, 0xffff3b1f],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Los discos se voltean en ondas continuas: a 60 FPS es fluido.
  framesPerSecond: 60,
);
