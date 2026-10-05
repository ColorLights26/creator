import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'cristal_bismuto',
  name: 'Cristal de Bismuto',
  publication: CreatorPublication.draft,
  description:
      'Cristales de bismuto en escalera con terrazas metálicas de oro, naranja y rojo; la música corre olas de color por los escalones y enciende destellos en las aristas.',
  purposes: ['visualizer', 'focus', 'relax'],
  moods: ['metallic', 'geometric', 'luxurious'],
  concepts: ['bismuth', 'hopper crystal', 'iridescence', 'oxide'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff080406, 0xffd0102a, 0xffff6a00, 0xffffd040],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Los cristales se mueven despacio: 30 FPS bastan.
  framesPerSecond: 30,
);
