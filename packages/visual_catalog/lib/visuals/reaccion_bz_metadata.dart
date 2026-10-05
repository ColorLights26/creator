import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reaccion_bz',
  name: 'Reacción BZ',
  publication: CreatorPublication.draft,
  description:
      'La reacción química de Belousov-Zhabotinsky: espirales y anillos de color que avanzan, chocan y se anulan; con la música nacen focos nuevos y la química se acelera.',
  purposes: ['visualizer', 'focus', 'relax'],
  moods: ['hypnotic', 'organic', 'scientific'],
  concepts: ['belousov-zhabotinsky', 'chemical waves', 'excitable media', 'spirals'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 10),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff12030a, 0xff8c0a1e, 0xffff4a12, 0xffffc23a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las ondas avanzan despacio: 30 FPS bastan.
  framesPerSecond: 30,
);
