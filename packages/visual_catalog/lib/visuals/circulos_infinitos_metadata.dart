import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'circulos_infinitos',
  name: 'Círculos Infinitos',
  publication: CreatorPublication.draft,
  description:
      'Espiral de círculos tangentes que se encogen sin fin hacia el centro, con círculos dentro de los círculos: un zoom infinito y perfecto en verde ácido que late con la música.',
  purposes: ['visualizer', 'focus', 'party'],
  moods: ['hypnotic', 'mathematical', 'electric'],
  concepts: ['doyle spiral', 'infinite zoom', 'circle packing', 'log polar'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff000604, 0xffa8ff00, 0xff00e0c8, 0xffffffff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Zoom continuo hacia el centro: a 60 FPS es fluido.
  framesPerSecond: 30,
);
