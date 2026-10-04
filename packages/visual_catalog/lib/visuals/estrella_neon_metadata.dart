import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'estrella_neon',
  name: 'Estrella de Neón',
  publication: CreatorPublication.draft,
  description:
      'Caleidoscopio de seis puntas: estrellas de neón dorado salen del centro, láseres azules cruzan la pantalla y mármol rojo y naranja estalla con la música.',
  purposes: ['party', 'club', 'visualizer'],
  moods: ['epic', 'psychedelic', 'intense'],
  concepts: ['hexagram', 'kaleidoscope', 'lasers', 'marble'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3.0),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff01020a, 0xff2a5bff, 0xffffb21f, 0xffff2a14],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Estrellas que salen sin parar: a 60 FPS el movimiento es fluido.
  framesPerSecond: 60,
);
