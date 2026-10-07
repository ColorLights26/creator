import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'rorschach_cosmico',
  name: 'Rorschach Cósmico',
  publication: CreatorPublication.draft,
  description:
      'Una nebulosa con forma de mancha de Rorschach: gas rojo, naranja y dorado con filamentos y franjas de polvo oscuro, un cúmulo de estrellas en el centro y ondas de supernova que la recorren con cada golpe.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['cosmic', 'mind-blowing', 'dreamy'],
  concepts: ['rorschach', 'nebula', 'supernova', 'stars'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 4),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff030208, 0xffb0102a, 0xffff5a14, 0xffffb21a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta cambia de forma sin parar: a 60 FPS es fluido.
  framesPerSecond: 30, // energía: ver energy/frame_rate_record.json
);
