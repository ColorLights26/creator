import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'estela_magica',
  name: 'Estela Mágica',
  publication: CreatorPublication.draft,
  description:
      'Luces mágicas que vuelan haciendo espirales y ondas y dejan una cinta brillante con hebras que se enroscan y un rastro de polvo de estrellas que titila y cae. Sin fondo, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['magical', 'dreamy', 'festive'],
  concepts: ['magic trail', 'sparkles', 'light ribbon', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffa8123e, 0xffffa21a, 0xfffff3d6],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas simuladas con física: fluidas a 30 FPS en el móvil.
  framesPerSecond: 30,
);
