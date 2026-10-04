import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'un_bit',
  name: '1-Bit',
  publication: CreatorPublication.draft,
  description:
      'Escena 3D en un solo bit, como el juego Obra Dinn: un cubo y esferas rojas que orbitan, dibujados sólo con tramas de puntos blancos sobre negro; todo late con la música.',
  purposes: ['visualizer', 'focus', 'party'],
  moods: ['retro', 'graphic', 'minimal'],
  concepts: ['1-bit', 'dithering', 'obra dinn', 'bayer'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff050505, 0xfff2ead8, 0xffff1e1e, 0xff2a2a2a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // El cubo gira y las esferas orbitan sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
