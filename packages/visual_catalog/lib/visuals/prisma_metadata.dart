import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'prisma',
  name: 'Prisma',
  publication: CreatorPublication.draft,
  description:
      'Un haz de luz blanca entra en un prisma de cristal y sale convertido en arcoíris; cada color late con su banda de la música.',
  purposes: ['visualizer', 'relax', 'party'],
  moods: ['iconic', 'minimal', 'hypnotic'],
  concepts: ['prism', 'rainbow', 'light dispersion', 'album art'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff000000, 0xffffffff, 0xffc9d0e0, 0xff7a8296],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // El haz y el arcoíris laten sin parar: a 60 FPS es fluido.
  framesPerSecond: 30,
);
