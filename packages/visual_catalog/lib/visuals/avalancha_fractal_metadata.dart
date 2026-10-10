import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'avalancha_fractal',
  name: 'Avalancha Fractal',
  publication: CreatorPublication.draft,
  description:
      'Granos que se apilan en el centro y se derrumban según una regla simple: de las avalanchas crece un mandala fractal perfecto en rojo, naranja y amarillo que se expande con la música.',
  purposes: ['visualizer', 'focus', 'relax'],
  moods: ['mathematical', 'hypnotic', 'satisfying'],
  concepts: ['abelian sandpile', 'self-organized criticality', 'fractal', 'cellular automaton'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 14),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff070205, 0xffc8101e, 0xffff7a00, 0xffffe14a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las avalanchas se calculan a 60 pasos por segundo.
  framesPerSecond: 30,
);
