import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'brasas_cinematicas',
  name: 'Brasas Cinemáticas',
  publication: CreatorPublication.draft,
  description:
      'Fondo de cine oscuro: humo que se arremolina iluminado por un foco de brasas encendidas en el centro, y brasas sueltas que flotan por todo el plano, algunas cerca y desenfocadas. Sin fondo, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['cinematic', 'dark', 'epic'],
  concepts: ['embers', 'smoke', 'fire', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff6a1a08, 0xffff6a14, 0xffffc66b],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas simuladas con física: fluidas a 30 FPS en el móvil.
  framesPerSecond: 30,
);
