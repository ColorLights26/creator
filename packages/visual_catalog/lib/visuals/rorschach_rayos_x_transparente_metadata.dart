import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'rorschach_rayos_x_transparente',
  name: 'Rorschach Rayos X Transparente',
  publication: CreatorPublication.draft,
  description:
      'La mancha de Rorschach vista en negativo como una radiografía de un ser vivo: brilla con venas por dentro, late como un corazón y una franja de escáner la recorre. Sin fondo: se ve lo que hay detrás.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['disturbing', 'eerie', 'organic'],
  concepts: ['rorschach', 'x-ray', 'veins', 'heartbeat'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffff2a14, 0xffff9a3a, 0xffffe8c8],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta cambia de forma sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
