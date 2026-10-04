import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'arcos_sueno',
  name: 'Arcos del Sueño',
  publication: CreatorPublication.draft,
  description:
      'Pasillo infinito de arcos rojos, naranjas y dorados que se derriten, con un río ondulado de turquesa y crema hacia una puerta de luz; respira con la música.',
  purposes: ['visualizer', 'relax', 'psychedelic'],
  moods: ['surreal', 'psychedelic', 'dreamy'],
  concepts: ['arches', 'corridor', 'surrealism', 'tunnel'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff1a0301, 0xffd8220f, 0xffffa21f, 0xff23b3a8],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Avance continuo por el pasillo: a 60 FPS es fluido.
  framesPerSecond: 60,
);
