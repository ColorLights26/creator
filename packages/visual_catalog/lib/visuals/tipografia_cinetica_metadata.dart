import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'tipografia_cinetica',
  name: 'Tipografía Cinética',
  publication: CreatorPublication.draft,
  description:
      'Palabras gigantes que entran con cada golpe de la música, de golpe, cayendo o girando letra a letra, con filas de palabras que pasan detrás y un fogonazo rojo en cada golpe.',
  purposes: ['visualizer', 'party'],
  moods: ['bold', 'energetic', 'graphic'],
  concepts: ['kinetic typography', 'motion graphics', 'words', 'poster'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff0a0a0a, 0xffff1f1f, 0xffffd400, 0xfff5f0e6],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las letras entran de golpe: a 60 FPS es fluido.
  framesPerSecond: 30,
);
