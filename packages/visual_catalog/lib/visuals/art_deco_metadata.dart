import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'art_deco',
  name: 'Art Déco',
  publication: CreatorPublication.draft,
  description:
      'Ornamentos de oro sobre negro de los años veinte: un sol de rayos con arcos escalonados, abanicos que se abren en olas o la corona de un rascacielos, al ritmo de la música.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['luxurious', 'elegant', 'retro'],
  concepts: ['art deco', 'gatsby', 'sunburst', 'gold ornament'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 4),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff050505, 0xff8e0e1c, 0xffc8902c, 0xffffe08a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // El ornamento se mueve despacio: 30 FPS bastan.
  framesPerSecond: 30,
);
