import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'medidores_vu',
  name: 'Medidores VU',
  publication: CreatorPublication.draft,
  description:
      'Un panel de equipo de música antiguo: medidores analógicos con luz ámbar cuyas agujas bailan con cada banda de la música y piloto rojo que se enciende en cada golpe.',
  purposes: ['visualizer', 'relax', 'party'],
  moods: ['retro', 'warm', 'analog'],
  concepts: ['vu meter', 'hi-fi', 'needles', 'analog'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff0b0806, 0xffffa733, 0xffff2a14, 0xff1a1410],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las agujas tienen inercia real: a 60 FPS es fluido.
  framesPerSecond: 60,
);
