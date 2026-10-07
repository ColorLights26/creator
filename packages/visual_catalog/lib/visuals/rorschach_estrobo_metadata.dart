import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'rorschach_estrobo',
  name: 'Rorschach Estrobo',
  publication: CreatorPublication.draft,
  description:
      'Una mancha de Rorschach que cambia de forma de golpe con cada golpe de la música, salta entre dos, cuatro, seis y ocho espejos, invierte el blanco y el negro y hace temblar la pantalla.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['intense', 'aggressive', 'club'],
  concepts: ['rorschach', 'strobe', 'jump cut', 'kaleidoscope'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xfff4f0e8, 0xff050505, 0xffe0101e, 0xffffd400],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta cambia de forma sin parar: a 60 FPS es fluido.
  framesPerSecond: 30, // energía: ver energy/frame_rate_record.json
);
