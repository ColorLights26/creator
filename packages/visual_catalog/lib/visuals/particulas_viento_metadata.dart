import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'particulas_viento',
  name: 'Partículas al Viento',
  publication: CreatorPublication.draft,
  description:
      'Capa transparente de partículas que cruzan la pantalla de un lado a otro llevadas por el viento, ondulando con una estela corta, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['dynamic', 'elegant', 'cinematic'],
  concepts: ['wind', 'drifting particles', 'motion', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff9e0022, 0xffff2a4a, 0xffffc2c8],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas sencillas: a 30 FPS gastan poca batería.
  framesPerSecond: 30,
);
