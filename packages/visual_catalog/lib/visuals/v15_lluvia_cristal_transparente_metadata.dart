import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'v15_lluvia_cristal_transparente',
  name: 'Lluvia sobre Cristal Transparente',
  publication: CreatorPublication.draft,
  description: 'Gotas de lluvia realistas con física de escurrimiento, meniscos y reflejos cáusticos sobre cristal transparente.',
  purposes: ['relax', 'ambient'],
  moods: ['calm', 'rainy'],
  concepts: ['rain', 'glass', 'water'],
  credits: CreatorCredits(author: 'Visuales Inmersivas'),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0xff80d0ff, 0xffffffff, 0xff4080bf, 0xff102030],
  controls: CreatorControls(intensity: 1.0, speed: 1.0, detail: 1.0, glow: 1.0),
);
