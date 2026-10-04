import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'nucleo_cristal_transparente',
  name: 'Núcleo de Cristal Transparente',
  publication: CreatorPublication.draft,
  description:
      'Un cristal de luz en espejo late en el centro y lanza hacia fuera contornos de neón azul, naranja, rojo y blanco que cambian de forma con cada golpe sobre fondo transparente.',
  purposes: ['party', 'club', 'visualizer'],
  moods: ['epic', 'energetic', 'futuristic'],
  concepts: ['crystal', 'kaleidoscope', 'neon outlines', 'vj loop'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff1f7bff, 0xffffa040, 0xffff3dd2],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Contornos que salen sin parar: a 60 FPS el movimiento es fluido.
  framesPerSecond: 60,
);
