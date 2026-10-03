import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'ondas_voz',
  name: 'Ondas de Voz',
  publication: CreatorPublication.draft,
  description:
      'Ondas luminosas rosa, azul y verde que se cruzan y bailan como las de un asistente de voz; cada banda de la música mueve su onda.',
  purposes: ['visualizer', 'relax', 'party'],
  moods: ['modern', 'clean', 'vivid'],
  concepts: ['waveform', 'voice', 'waves', 'glow'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff03040a, 0xffff4f9a, 0xff3d8bff, 0xff3dffa6],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Ondas en movimiento continuo: a 60 FPS son fluidas.
  framesPerSecond: 60,
);
