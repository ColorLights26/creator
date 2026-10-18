import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'brasas',
  name: 'Brasas',
  publication: CreatorPublication.draft,
  description:
      'Capa transparente de brasas de fuego: chispitas naranjas y rojas que suben desde abajo parpadeando y se apagan en el aire, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['warm', 'cinematic', 'calm'],
  concepts: ['embers', 'fire', 'particles', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffd81e05, 0xffff6a00, 0xffffd166],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas sencillas: a 30 FPS gastan poca batería.
  framesPerSecond: 30,
);
