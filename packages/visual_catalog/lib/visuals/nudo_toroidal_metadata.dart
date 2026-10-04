import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'nudo_toroidal',
  name: 'Nudo Toroidal',
  publication: CreatorPublication.draft,
  description:
      'Un tubo de neón amarillo con franjas rojas anudado sobre sí mismo que gira en 3D; las franjas corren con la música y en cada frase el nudo se transforma en otro.',
  purposes: ['visualizer', 'focus', 'party'],
  moods: ['hypnotic', 'bold', 'mathematical'],
  concepts: ['torus knot', '3d', 'tube', 'topology'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff060300, 0xffffe000, 0xffff1a00, 0xffff7a00],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // El nudo gira y las franjas corren sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
