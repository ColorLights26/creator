import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_v10_supernova_transparente',
  name: 'Reactiva · Supernova & Termodinámica',
  publication: CreatorPublication.draft,
  description: 'Versión reactiva: sin música no dibuja nada y sólo aparece un instante con el golpe grande (o el momento que elijas en Ajustes) y desaparece. Explosión estelar relativista con ondas de choque expansivas y partículas termodinámicas sobre fondo transparente.',
  purposes: ['physics', 'visualizer', 'epic'],
  moods: ['explosive', 'intense', 'cosmic'],
  concepts: ['aparición momentánea', 'supernova', 'shockwave', 'thermodynamics', 'stellar explosion'],
  credits: CreatorCredits(author: 'Visuales Inmersivas', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.2),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff5722, 0xffffd600, 0xff00e5ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
