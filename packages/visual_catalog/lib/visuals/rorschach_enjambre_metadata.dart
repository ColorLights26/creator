import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'rorschach_enjambre',
  name: 'Rorschach Enjambre',
  publication: CreatorPublication.draft,
  description:
      'Una mancha de Rorschach hecha de miles de bichos que se mueven sin parar: hormigas, moscas o gusanos que forman la figura y se dispersan con cada golpe de la música.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['disturbing', 'creepy', 'organic'],
  concepts: ['rorschach', 'swarm', 'insects', 'crawling'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xffe9dfc9, 0xff100b08, 0xff8a0f0f, 0xffffcf8a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta cambia de forma sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
