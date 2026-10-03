import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'pantalla_led_transparente',
  name: 'Pantalla LED Transparente',
  publication: CreatorPublication.draft,
  description:
      'Pared de LEDs de concierto en rojo y blanco: anillos, barridos, barras del espectro y estrobos que cambian con cada compás sobre fondo transparente.',
  purposes: ['party', 'visualizer', 'club'],
  moods: ['energetic', 'epic', 'stage'],
  concepts: ['led wall', 'stage', 'pixels', 'strobe'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffff1a12, 0xffffe6d2, 0xff5a0000],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Barridos y anillos continuos: a 60 FPS el movimiento es fluido.
  framesPerSecond: 60,
);
