import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'luciernagas_simples',
  name: 'Luciérnagas Simples',
  publication: CreatorPublication.draft,
  description:
      'Capa transparente de luciérnagas: puntos verde amarillo que vagan despacio y se encienden y se apagan, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['calm', 'magical', 'romantic'],
  concepts: ['fireflies', 'blinking lights', 'night', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff3f6b00, 0xffb6f000, 0xfff4ff9a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas sencillas: a 30 FPS gastan poca batería.
  framesPerSecond: 30,
);
