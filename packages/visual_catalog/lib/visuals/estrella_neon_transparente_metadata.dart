import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'estrella_neon_transparente',
  name: 'Estrella de Neón Transparente',
  publication: CreatorPublication.draft,
  description:
      'Caleidoscopio de seis puntas: estrellas de neón dorado salen del centro, láseres azules cruzan la pantalla y mármol rojo y naranja estalla con la música sobre fondo transparente.',
  purposes: ['party', 'club', 'visualizer'],
  moods: ['epic', 'psychedelic', 'intense'],
  concepts: ['hexagram', 'kaleidoscope', 'lasers', 'marble'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3.0),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff2a5bff, 0xffffb21f, 0xffff2a14],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Estrellas que salen sin parar: a 60 FPS el movimiento es fluido.
  framesPerSecond: 60,
);
