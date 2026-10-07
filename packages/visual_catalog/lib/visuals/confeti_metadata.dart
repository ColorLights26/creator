import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'confeti',
  name: 'Confeti',
  publication: CreatorPublication.draft,
  description:
      'Capa transparente de fiesta: cañones de confeti de colores que disparan con cada golpe y papelitos que caen girando en 3D sobre cualquier otro visual.',
  purposes: ['party', 'celebration', 'visualizer'],
  moods: ['festive', 'playful', 'joyful'],
  concepts: ['confetti', 'celebration', 'overlay', 'physics'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffff2a2a, 0xffffd400, 0xff2a6bff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Cada papelito gira y cae con física: a 60 FPS es fluido.
  framesPerSecond: 30, // energía: ver energy/frame_rate_record.json
);
