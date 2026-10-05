import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'rorschach_neon',
  name: 'Rorschach Neón',
  publication: CreatorPublication.draft,
  description:
      'Una mancha de Rorschach dibujada con tubos de neón rojos, naranjas y amarillos sobre una pared de ladrillo; zumban, parpadean y se encienden a tope con cada golpe de la música.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['nightlife', 'electric', 'retro'],
  concepts: ['rorschach', 'neon sign', 'glow', 'brick wall'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff0d0708, 0xffff1f3d, 0xffff8a00, 0xffffd84a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta cambia de forma sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
