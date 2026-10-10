import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'bauhaus',
  name: 'Bauhaus',
  publication: CreatorPublication.draft,
  description:
      'Un póster Bauhaus animado: círculos, medias lunas, cuartos de círculo, triángulos y franjas en rojo, amarillo, azul y negro sobre crema que giran y cambian a golpe de música.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['graphic', 'bold', 'playful'],
  concepts: ['bauhaus', 'geometric', 'flat design', 'poster'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xfff2e8d5, 0xffe63312, 0xfff5b700, 0xff1d3fbb],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las piezas giran y saltan con rebote: a 60 FPS es fluido.
  framesPerSecond: 30,
);
