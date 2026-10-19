import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'hiperespacio',
  name: 'Hiperespacio',
  publication: CreatorPublication.draft,
  description:
      'Capa transparente de hiperespacio: puntos de luz que salen del centro hacia los bordes cada vez más deprisa, como viajar a la velocidad de la luz, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['energetic', 'futuristic', 'epic'],
  concepts: ['hyperspace', 'warp', 'stars', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff4a6dff, 0xffc9d6ff, 0xffffffff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas sencillas: a 30 FPS gastan poca batería.
  framesPerSecond: 30,
);
