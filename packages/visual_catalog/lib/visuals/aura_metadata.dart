import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'aura',
  name: 'Aura',
  publication: CreatorPublication.draft,
  description:
      'Manchas de color melocotón, lila y azul que giran y se funden despacio con grano fino, respirando con la música.',
  purposes: ['relax', 'focus', 'visualizer'],
  moods: ['calm', 'dreamy', 'elegant'],
  concepts: ['gradient', 'aura', 'blur', 'color'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff1a1030, 0xffffb89a, 0xffc79bff, 0xff7fb6ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Movimiento lento y continuo: a 60 FPS los degradados fluyen suaves.
  framesPerSecond: 30,
);
