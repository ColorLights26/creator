import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'nieve_premium',
  name: 'Nieve Premium',
  publication: CreatorPublication.draft,
  description:
      'Nieve de cine: copos suaves que caen meciéndose, los lejanos diminutos y nítidos, los cercanos grandes y desenfocados, con un brillo frío. Sin fondo, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['calm', 'dreamy', 'cozy'],
  concepts: ['snow', 'depth of field', 'winter', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff8fa9d6, 0xffe6eeff, 0xffffffff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas simuladas con física: fluidas a 30 FPS en el móvil.
  framesPerSecond: 30,
);
