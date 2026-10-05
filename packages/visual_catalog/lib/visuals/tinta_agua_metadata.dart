import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'tinta_agua',
  name: 'Tinta en Agua',
  publication: CreatorPublication.draft,
  description:
      'Gotas de tinta roja, naranja y ámbar que caen en agua oscura y se abren en hongos, volutas y nubes en cámara lenta; cada golpe de la música suelta una gota nueva.',
  purposes: ['visualizer', 'relax', 'focus'],
  moods: ['fluid', 'dreamy', 'elegant'],
  concepts: ['ink in water', 'slow motion', 'plumes', 'fluid'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 7),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff020102, 0xffb0001e, 0xffff5a00, 0xffffb21a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta se mueve despacio: 30 FPS bastan.
  framesPerSecond: 30,
);
