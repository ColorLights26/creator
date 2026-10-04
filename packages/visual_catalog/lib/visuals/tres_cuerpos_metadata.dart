import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'tres_cuerpos',
  name: 'Tres Cuerpos',
  publication: CreatorPublication.draft,
  description:
      'Estrellas que bailan atraídas por su gravedad real: la famosa órbita en forma de ocho, triángulos que giran y lanzamientos caóticos, con estelas de fuego que laten con la música.',
  purposes: ['visualizer', 'focus', 'relax'],
  moods: ['cosmic', 'hypnotic', 'dramatic'],
  concepts: ['three-body problem', 'gravity', 'orbits', 'chaos'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff020105, 0xffff2a1a, 0xffffb000, 0xffffe9b0],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La gravedad se calcula a 480 pasos por segundo.
  framesPerSecond: 60,
);
