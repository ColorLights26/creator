import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'murmuracion_transparente',
  name: 'Murmuración Transparente',
  publication: CreatorPublication.draft,
  description:
      'Miles de chispas doradas vuelan juntas como una bandada de estorninos: se estiran, giran y se pliegan, y estallan con cada golpe sobre fondo transparente.',
  purposes: ['visualizer', 'relax', 'party'],
  moods: ['hypnotic', 'organic', 'epic'],
  concepts: ['murmuration', 'flock', 'particles', 'emergence'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffffb000, 0xffff5a00, 0xfffff0c0],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La bandada vuela sin parar: a 60 FPS el movimiento es fluido.
  framesPerSecond: 30, // energía: ver energy/frame_rate_record.json
);
