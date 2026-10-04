import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'ojo_psicodelico_transparente',
  name: 'Ojo Psicodélico Transparente',
  publication: CreatorPublication.draft,
  description:
      'Un ojo gigante de iris turquesa y dorado mira a su alrededor rodeado de ondas rojas y naranjas que se derriten; la pupila late con los graves sobre fondo transparente.',
  purposes: ['visualizer', 'party', 'psychedelic'],
  moods: ['surreal', 'psychedelic', 'hypnotic'],
  concepts: ['eye', 'surrealism', 'melting', 'psychedelic art'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffe8261a, 0xffffa31a, 0xff1fb5b0],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Ondas y mirada en movimiento continuo: a 60 FPS es fluido.
  framesPerSecond: 60,
);
