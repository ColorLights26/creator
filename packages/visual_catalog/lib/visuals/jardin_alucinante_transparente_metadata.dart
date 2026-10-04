import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'jardin_alucinante_transparente',
  name: 'Jardín Alucinante Transparente',
  publication: CreatorPublication.draft,
  description:
      'Flores psicodélicas de póster setentero en magenta, naranja, amarillo y turquesa que giran y florecen con cada golpe sobre un sol de rayos sobre fondo transparente.',
  purposes: ['visualizer', 'party', 'psychedelic'],
  moods: ['psychedelic', 'joyful', 'retro'],
  concepts: ['flower power', 'psychedelic', 'bloom', 'poster art'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffff1f8f, 0xffff8a00, 0xff00d1c1],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Flores que giran y florecen: a 60 FPS es fluido.
  framesPerSecond: 60,
);
