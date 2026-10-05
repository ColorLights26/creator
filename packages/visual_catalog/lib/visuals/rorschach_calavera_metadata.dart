import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'rorschach_calavera',
  name: 'Rorschach Calavera',
  publication: CreatorPublication.draft,
  description:
      'En el hueco de la mancha de Rorschach aparece una calavera con cuencas en las que brillan dos brasas; la mandíbula castañea o habla y con cada golpe de la música se abre en una carcajada.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['disturbing', 'dark', 'gothic'],
  concepts: ['rorschach', 'skull', 'memento mori', 'negative space'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xffece3d0, 0xff0a0707, 0xffd0141e, 0xffffb21a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta cambia de forma sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
