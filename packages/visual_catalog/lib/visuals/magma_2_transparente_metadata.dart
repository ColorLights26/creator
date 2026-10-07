import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'magma_2_transparente',
  name: 'Magma 2 Transparente',
  publication: CreatorPublication.draft,
  description:
      'Corteza volcánica viva: las grietas de lava se retuercen y se desplazan, por ellas corren pulsos de roca fundida y cada golpe lanza una onda de calor que las abre sobre fondo transparente.',
  purposes: ['visualizer', 'party'],
  moods: ['intense', 'warm', 'epic'],
  concepts: ['lava', 'magma', 'cracks', 'embers', 'shockwave'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffd41a00, 0xffff7a00, 0xffffd24a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Grietas y pulsos en movimiento continuo: a 60 FPS es fluido.
  framesPerSecond: 30, // energía: ver energy/frame_rate_record.json
);
