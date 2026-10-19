import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'luces_flotantes_premium',
  name: 'Luces Flotantes Premium',
  publication: CreatorPublication.draft,
  description:
      'Bokeh de cine: lucecitas rojas y rosadas con el centro brillante y luces cercanas grandes y desenfocadas que flotan despacio, con un resplandor que entra por una esquina. Sin fondo, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['romantic', 'dreamy', 'elegant'],
  concepts: ['bokeh', 'floating lights', 'depth of field', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffb3002a, 0xffff3b6b, 0xffffc4a8],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas simuladas con física: fluidas a 30 FPS en el móvil.
  framesPerSecond: 30,
);
