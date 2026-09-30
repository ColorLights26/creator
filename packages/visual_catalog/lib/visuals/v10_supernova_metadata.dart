import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'v10_supernova',
  name: 'Supernova & Termodinámica',
  publication: CreatorPublication.draft,
  description: 'Explosión estelar relativista con ondas de choque expansivas, 360 partículas termodinámicas con estelas de velocidad y púlsar central.',
  purposes: ['physics', 'visualizer', 'epic'],
  moods: ['explosive', 'intense', 'cosmic'],
  concepts: ['supernova', 'shockwave', 'thermodynamics', 'stellar explosion'],
  credits: CreatorCredits(author: 'Visuales Inmersivas', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff030107, 0xffff5722, 0xffffd600, 0xff00e5ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
