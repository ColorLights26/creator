import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'celulas_voronoi',
  name: 'Células de Voronoi',
  publication: CreatorPublication.draft,
  description:
      'Un tejido de células de Voronoi con membranas brillantes y núcleos que se mueven y se dividen; cada golpe de la música parte media pantalla y los agudos mandan impulsos por las membranas.',
  purposes: ['visualizer', 'focus', 'relax'],
  moods: ['organic', 'alive', 'scientific'],
  concepts: ['voronoi', 'cells', 'mitosis', 'tissue'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff0a0203, 0xff8a0f05, 0xffff5a1a, 0xffffd27a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las células se mueven despacio: 30 FPS bastan.
  framesPerSecond: 30,
);
