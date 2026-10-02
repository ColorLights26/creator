import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'v10_supernova_transparente',
  name: 'Supernova & Termodinámica Transparente',
  publication: CreatorPublication.draft,
  description: 'Explosión estelar relativista con ondas de choque expansivas y partículas termodinámicas sobre fondo transparente.',
  purposes: ['physics', 'visualizer', 'epic'],
  moods: ['explosive', 'intense', 'cosmic'],
  concepts: ['supernova', 'shockwave', 'thermodynamics', 'stellar explosion'],
  credits: CreatorCredits(author: 'Visuales Inmersivas', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffff5722, 0xffffd600, 0xff00e5ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
