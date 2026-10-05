import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'rorschach_hipnotico',
  name: 'Rorschach Hipnótico',
  publication: CreatorPublication.draft,
  description:
      'Una mancha de Rorschach de la que salen ecos de su propia forma en bandas blancas y negras que fluyen sin parar hacia dentro o hacia fuera, como una ilusión óptica que te atrapa.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['hypnotic', 'psychedelic', 'intense'],
  concepts: ['rorschach', 'op art', 'contour echoes', 'hypnosis'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xfff2ebdd, 0xff0a0606, 0xffd0101e, 0xffff7a1a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta cambia de forma sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
