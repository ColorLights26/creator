import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'rorschach_hipnotico',
  name: 'Rorschach Hipnótico',
  publication: CreatorPublication.draft,
  description:
      'Ecos de una mancha de Rorschach en bandas blancas y negras que fluyen al ritmo: cada golpe las empuja y lanza una onda que las deforma, los graves cambian cuántas hay y la mancha muta sin parar.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['hypnotic', 'psychedelic', 'intense'],
  concepts: ['rorschach', 'op art', 'contour echoes', 'hypnosis'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 4),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xfff2ebdd, 0xff0a0606, 0xffd0101e, 0xffff7a1a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta cambia de forma sin parar: a 60 FPS es fluido.
  framesPerSecond: 30, // energía: ver energy/frame_rate_record.json
);
