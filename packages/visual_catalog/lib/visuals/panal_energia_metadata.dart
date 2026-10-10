import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'panal_energia',
  name: 'Panal de Energía',
  publication: CreatorPublication.draft,
  description:
      'Un escudo de energía de hexágonos ámbar: cada golpe es un impacto que enciende las celdas en rojo y lanza una onda de luz por todo el panal.',
  purposes: ['visualizer', 'party', 'club'],
  moods: ['futuristic', 'energetic', 'warm'],
  concepts: ['hexagon', 'energy shield', 'sci-fi', 'impact'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff070300, 0xffff8c00, 0xffff2a00, 0xffffe2b0],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Ondas y destellos rápidos: a 60 FPS es fluido.
  framesPerSecond: 30,
);
