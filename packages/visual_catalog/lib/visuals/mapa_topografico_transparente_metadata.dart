import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'mapa_topografico_transparente',
  name: 'Mapa Topográfico Transparente',
  publication: CreatorPublication.draft,
  description:
      'Curvas de nivel rojas de un terreno vivo sobre negro: con los graves las montañas crecen y las líneas se aprietan, y cada golpe levanta una cumbre que se enciende sobre fondo transparente.',
  purposes: ['visualizer', 'focus', 'relax'],
  moods: ['minimal', 'hypnotic', 'warm'],
  concepts: ['topographic map', 'contour lines', 'terrain', 'elevation'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffff1a10, 0xffff7a00, 0xffffd84a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // El terreno fluye sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
