import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'v06_tesseract_4d_transparente',
  name: 'Hipercubo 4D Tesseract Transparente',
  publication: CreatorPublication.draft,
  description: 'Proyección 4D de hipercubo transparente rotando en planos XW e YZ con aristas luminosas y núcleo reactivo.',
  purposes: ['hud', 'geometry'],
  moods: ['mystic', 'cosmic'],
  concepts: ['tesseract', '4d', 'geometry'],
  credits: CreatorCredits(author: 'Visuales Inmersivas'),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0xff9d4edd, 0xff00f0ff, 0xffffffff, 0xff240046],
  controls: CreatorControls(intensity: 1.0, speed: 1.0, detail: 1.0, glow: 1.0),
);
