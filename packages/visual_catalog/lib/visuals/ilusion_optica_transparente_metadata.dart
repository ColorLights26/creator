import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'ilusion_optica_transparente',
  name: 'Ilusión Óptica Transparente',
  publication: CreatorPublication.draft,
  description:
      'Patrones op art en rojo, negro y blanco que parecen moverse, respirar y hundirse aunque son planos; laten y se deforman con cada golpe sobre fondo transparente.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['hypnotic', 'bold', 'trippy'],
  concepts: ['op art', 'optical illusion', 'moire', 'bridget riley'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffff1a1a, 0xffffffff, 0xff7a0000],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Patrones en movimiento continuo: a 60 FPS la ilusión es fluida.
  framesPerSecond: 60,
);
