import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_luciernagas_transparente',
  name: 'Reactiva Mejorada · Luciérnagas Sincronizadas',
  publication: CreatorPublication.draft,
  description:
      'Versión reactiva mejorada: sin música no dibuja nada; con música se ve tanto como suena y cada golpe la enciende más. Cientos de luciérnagas que parpadean al azar y poco a poco se ponen de acuerdo hasta encenderse todas a la vez; con música, cada golpe las sincroniza con el ritmo sobre fondo transparente.',
  purposes: ['visualizer', 'relax', 'focus'],
  moods: ['magical', 'organic', 'calm'],
  concepts: ['aparición momentánea', 'reactiva mejorada', 'fireflies', 'synchronization', 'kuramoto', 'emergence'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.2),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffb8ff1a, 0xffffc21a, 0xffff5a14],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Los destellos son rápidos: a 60 FPS es fluido.
  framesPerSecond: 30,
);
