import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'vidrio_liquido',
  name: 'Vidrio Líquido',
  publication: CreatorPublication.draft,
  description:
      'Gotas de vidrio líquido que se funden y se separan refractando un degradado naranja y azul, con brillos que siguen la música.',
  purposes: ['visualizer', 'relax', 'focus'],
  moods: ['modern', 'elegant', 'fluid'],
  concepts: ['liquid glass', 'refraction', 'metaballs', 'gradient'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff0a0a14, 0xffff7a1a, 0xff2d6bff, 0xffffffff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las gotas fluyen sin parar: a 60 FPS el vidrio se mueve con suavidad.
  framesPerSecond: 30,
);
