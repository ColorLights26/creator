import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'anillos_humo',
  name: 'Anillos de Humo',
  publication: CreatorPublication.draft,
  description:
      'Aros de humo que salen disparados desde abajo, girando sobre sí mismos y creciendo hasta deshacerse, iluminados por un foco; cada golpe de la música dispara uno nuevo.',
  purposes: ['visualizer', 'party', 'relax'],
  moods: ['smoky', 'hypnotic', 'cinematic'],
  concepts: ['vortex rings', 'smoke', 'air cannon', 'stage light'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 6),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff050203, 0xffc0141c, 0xffff6a10, 0xffffd7a0],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // El humo rueda rápido: a 60 FPS es fluido.
  framesPerSecond: 30,
);
