import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'juego_vida_transparente',
  name: 'Juego de la Vida Transparente',
  publication: CreatorPublication.draft,
  description:
      'El autómata de Conway en neón: células que nacen en blanco, maduran en naranja y mueren en rojo, naves que cruzan la pantalla y explosiones de vida con cada golpe sobre fondo transparente.',
  purposes: ['visualizer', 'focus', 'party'],
  moods: ['digital', 'organic', 'energetic'],
  concepts: ['game of life', 'cellular automaton', 'emergence', 'pixels'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 4),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffff2a00, 0xffff9500, 0xffffef9a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las generaciones cambian a saltos y las brasas se apagan suave.
  framesPerSecond: 30,
);
