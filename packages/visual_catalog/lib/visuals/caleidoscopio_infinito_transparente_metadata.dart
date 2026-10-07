import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'caleidoscopio_infinito_transparente',
  name: 'Caleidoscopio Infinito Transparente',
  publication: CreatorPublication.draft,
  description:
      'Viaje sin fin hacia un mandala de geometría de neón que empuja, destella y cambia de simetría con los golpes sobre fondo transparente.',
  purposes: ['party', 'visualizer', 'relax'],
  moods: ['hypnotic', 'epic', 'psychedelic'],
  concepts: ['kaleidoscope', 'mandala', 'sacred geometry', 'infinite zoom'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffff2bd1, 0xff22d3ff, 0xffffc21f],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Viaje continuo hacia el centro: a 60 FPS el avance es perfectamente fluido.
  framesPerSecond: 30, // energía: ver energy/frame_rate_record.json
);
