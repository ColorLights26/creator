import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'moho_luminoso_transparente',
  name: 'Moho Luminoso Transparente',
  publication: CreatorPublication.draft,
  description:
      'Red viva de venas de luz roja y amarilla que crece, se ramifica y se reorganiza sola; cada golpe suelta una explosión de filamentos sobre fondo transparente.',
  purposes: ['visualizer', 'party', 'relax'],
  moods: ['organic', 'hypnotic', 'epic'],
  concepts: ['physarum', 'slime mold', 'generative', 'network'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3.0),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffff2200, 0xffffae00, 0xfffff2b0],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La red se mueve sin parar: a 60 FPS los filamentos fluyen.
  framesPerSecond: 30, // energía: 60 no cabe; ver energy/frame_rate_record.json
);
