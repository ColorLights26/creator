import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'rorschach_mercurio',
  name: 'Rorschach Mercurio',
  publication: CreatorPublication.draft,
  description:
      'Una mancha de Rorschach de metal líquido que refleja fuego o luces de estudio, con gotas sueltas que orbitan; cada golpe de la música manda una onda por la superficie.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['luxurious', 'fluid', 'hypnotic'],
  concepts: ['rorschach', 'liquid metal', 'chrome', 'mercury'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff07060a, 0xff5a0a06, 0xffff5a14, 0xffffe2b0],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta cambia de forma sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
