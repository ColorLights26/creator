import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'escalera_imposible',
  name: 'Escalera Imposible',
  publication: CreatorPublication.draft,
  description:
      'La escalera infinita de Escher y Penrose en isométrico: siempre sube y nunca termina, con pulsos de luz que trepan al ritmo de la música.',
  purposes: ['visualizer', 'focus', 'relax'],
  moods: ['surreal', 'hypnotic', 'clean'],
  concepts: ['penrose stairs', 'impossible geometry', 'isometric', 'escher'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff0a0f2e, 0xffff5a4e, 0xffffd23a, 0xff2f6bff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Pulsos que suben sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
