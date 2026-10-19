import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'luces_flotantes',
  name: 'Luces Flotantes',
  publication: CreatorPublication.draft,
  description:
      'Capa transparente de luces flotantes: puntos de luz rojos y rosados, suaves y desenfocados, que suben o flotan despacio y se encienden y se apagan, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['romantic', 'calm', 'dreamy'],
  concepts: ['bokeh', 'floating lights', 'particles', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffc8102e, 0xffff4f6d, 0xffffc7a8],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas sencillas: a 30 FPS gastan poca batería.
  framesPerSecond: 30,
);
