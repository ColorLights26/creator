import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'derretimiento',
  name: 'Derretimiento',
  publication: CreatorPublication.draft,
  description:
      'Bandas de color psicodélicas en rojo, naranja, magenta y turquesa que se ondulan y gotean como pintura derretida al ritmo de la música.',
  purposes: ['visualizer', 'party', 'psychedelic'],
  moods: ['psychedelic', 'surreal', 'fluid'],
  concepts: ['melting', 'psychedelic', 'drip', 'bands'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff0d0005, 0xffff2a1a, 0xffff9a00, 0xff00c8b4],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La pintura fluye sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
