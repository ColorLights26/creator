import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'hipervelocidad_transparente',
  name: 'Hipervelocidad Transparente',
  publication: CreatorPublication.draft,
  description: 'Viaje a la velocidad de la luz entre estrellas con estelas blancas y azules sobre fondo transparente.',
  purposes: ['party', 'visualizer'],
  moods: ['energetic', 'cosmic'],
  concepts: ['warp', 'stars', 'speed'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffffffff, 0xffbfe4ff, 0xffffd6f0],
  controls: CreatorControls(intensity: 1, speed: .8, detail: 1, glow: .9),
);
