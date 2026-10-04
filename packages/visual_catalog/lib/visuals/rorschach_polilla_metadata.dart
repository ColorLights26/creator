import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'rorschach_polilla',
  name: 'Rorschach Polilla',
  publication: CreatorPublication.draft,
  description:
      'La mancha de Rorschach cobra vida como una polilla gigante: sus alas de tinta baten al ritmo de la música y en ellas se abren ojos de fuego que te observan.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['eerie', 'organic', 'hypnotic'],
  concepts: ['rorschach', 'moth', 'eyespots', 'wings'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xffe6dcc6, 0xff0c0807, 0xffff6a00, 0xffffd21a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta cambia de forma sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
