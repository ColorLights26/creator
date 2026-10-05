import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'rorschach_cosmico',
  name: 'Rorschach Cósmico',
  publication: CreatorPublication.draft,
  description:
      'Una mancha de Rorschach que es una ventana al espacio: dentro hay nebulosas, una galaxia o estrellas que viajan hacia ti, con un borde que brilla como un horizonte de sucesos.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['cosmic', 'mind-blowing', 'dreamy'],
  concepts: ['rorschach', 'nebula', 'galaxy', 'portal'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xffefe6d4, 0xff1a0508, 0xffff4a1a, 0xffffd38a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta cambia de forma sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
