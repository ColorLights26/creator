import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'tubo_rubens',
  name: 'Tubo de Rubens',
  publication: CreatorPublication.draft,
  description:
      'Una fila de llamas sobre un tubo que dibujan el sonido: ondas estacionarias, el espectro de la canción o una onda viajera; cada golpe cambia el modo de la onda y aviva el fuego.',
  purposes: ['visualizer', 'party'],
  moods: ['fiery', 'scientific', 'intense'],
  concepts: ["rubens' tube", 'standing waves', 'flames', 'acoustics'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff040306, 0xff2a5cff, 0xffff6a00, 0xffffd75a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las llamas parpadean rápido: a 60 FPS es fluido.
  framesPerSecond: 30,
);
