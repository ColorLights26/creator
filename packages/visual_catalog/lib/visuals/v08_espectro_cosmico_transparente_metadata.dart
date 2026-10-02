import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'v08_espectro_cosmico_transparente',
  name: 'Espectro Sonoro Cósmico Transparente',
  publication: CreatorPublication.draft,
  description: 'Ecualizador radial transparente de 72 barras con núcleo reactivo a los graves y chispas de agudos.',
  purposes: ['visualizer', 'hud'],
  moods: ['energetic', 'futuristic'],
  concepts: ['spectrum', 'audio', 'circle'],
  credits: CreatorCredits(author: 'Visuales Inmersivas v08 (Overlay)'),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0xff00f0ff, 0xffff0080, 0xffffffff, 0xff200040],
  controls: CreatorControls(intensity: 1.0, speed: 1.0, detail: 1.0, glow: 1.0),
);
