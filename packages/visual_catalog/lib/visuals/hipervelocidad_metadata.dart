import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'hipervelocidad',
  name: 'Hipervelocidad',
  publication: CreatorPublication.draft,
  description: 'Viaje a la velocidad de la luz entre estrellas con estelas blancas y azules.',
  purposes: ['party', 'visualizer'],
  moods: ['energetic', 'cosmic'],
  concepts: ['warp', 'stars', 'speed'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff02020c, 0xffffffff, 0xffbfe4ff, 0xffffd6f0],
  controls: CreatorControls(intensity: 1, speed: .8, detail: 1, glow: .9),
);
