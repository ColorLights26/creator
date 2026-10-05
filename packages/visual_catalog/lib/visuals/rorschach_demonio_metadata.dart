import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'rorschach_demonio',
  name: 'Rorschach Demonio',
  publication: CreatorPublication.draft,
  description:
      'La mancha de Rorschach se convierte en un demonio con cuernos, ojos ardientes y una boca llena de colmillos que ruge con cada golpe de la música, entre brasas que suben.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['disturbing', 'dark', 'intense'],
  concepts: ['rorschach', 'demon', 'horns', 'fangs'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xffe6d8c0, 0xff0a0505, 0xffb0101a, 0xffffb21a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta cambia de forma sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
