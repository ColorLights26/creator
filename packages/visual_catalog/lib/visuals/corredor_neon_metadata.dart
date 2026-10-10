import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'corredor_neon',
  name: 'Corredor de Neón',
  publication: CreatorPublication.draft,
  description:
      'Corredor infinito de marcos de neón con paredes de cromo líquido que alterna entre rojo fuego y blanco helado; avanza y destella con cada golpe.',
  purposes: ['party', 'club', 'visualizer'],
  moods: ['intense', 'futuristic', 'hypnotic'],
  concepts: ['tunnel', 'corridor', 'neon frames', 'liquid chrome'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff000000, 0xffff2a00, 0xffffc21a, 0xff6fc8ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Avance continuo por el corredor: a 60 FPS es fluido.
  framesPerSecond: 30,
);
