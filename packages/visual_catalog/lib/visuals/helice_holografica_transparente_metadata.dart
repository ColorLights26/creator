import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'helice_holografica_transparente',
  name: 'Hélice Holográfica Transparente',
  publication: CreatorPublication.draft,
  description:
      'Doble hélice de ADN proyectada como holograma: gira en azul eléctrico, sus peldaños se encienden en rojo con las bandas de la música y cada golpe la hace temblar con un fallo digital sobre fondo transparente.',
  purposes: ['visualizer', 'focus', 'party'],
  moods: ['futuristic', 'scientific', 'electric'],
  concepts: ['dna', 'double helix', 'hologram', 'sci-fi'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff2aa8ff, 0xffa8f0ff, 0xffff2a4a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La hélice gira sin parar: a 60 FPS es fluido.
  framesPerSecond: 30,
);
