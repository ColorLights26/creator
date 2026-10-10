import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'pendulos_dobles',
  name: 'Caos de Péndulos Dobles',
  publication: CreatorPublication.draft,
  description:
      'Cientos de péndulos dobles casi idénticos se mueven como uno solo hasta que el caos los separa y estallan en un abanico de arcoíris; con la música vuelven a juntarse.',
  purposes: ['visualizer', 'focus', 'party'],
  moods: ['hypnotic', 'chaotic', 'vivid'],
  concepts: ['double pendulum', 'chaos', 'butterfly effect', 'physics'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 14),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff040208, 0xffff2a2a, 0xffffc400, 0xffa040ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La física avanza a 120 pasos por segundo: a 60 FPS es fluido.
  framesPerSecond: 30,
);
