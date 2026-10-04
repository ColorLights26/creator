import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'puerta_estelar',
  name: 'Puerta Estelar',
  publication: CreatorPublication.draft,
  description:
      'Dos planos de luz psicodélica en violeta, naranja y verde ácido pasan a toda velocidad hacia ti, como la puerta estelar de 2001; cambian con cada golpe.',
  purposes: ['visualizer', 'party', 'psychedelic'],
  moods: ['psychedelic', 'epic', 'hypnotic'],
  concepts: ['slit-scan', 'star gate', 'speed', 'retro sci-fi'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff000000, 0xff9b2cff, 0xffff7a00, 0xff9dff00],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Avance continuo a gran velocidad: a 60 FPS es fluido.
  framesPerSecond: 60,
);
