import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'haces_estadio_transparente',
  name: 'Haces de Estadio Transparente',
  publication: CreatorPublication.draft,
  description:
      'Iluminación de concierto: conos de luz de cabezas móviles que pulsan con cada golpe y cambian de coreografía y color con cada compás sobre fondo transparente.',
  purposes: ['party', 'visualizer'],
  moods: ['epic', 'energetic', 'concert'],
  concepts: ['stage lights', 'moving heads', 'beams', 'concert'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff3a5cff, 0xffff2fb4, 0xff35e8ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Haces anchos en movimiento: a 30 FPS se perciben a saltos.
  framesPerSecond: 30,
);
