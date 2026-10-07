import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'rorschach_plegado',
  name: 'Rorschach Plegado',
  publication: CreatorPublication.draft,
  description:
      'Así se hace una lámina de Rorschach, en directo: caen gotas de tinta en media hoja, la hoja se dobla, se aprieta y al abrirse aparece la mancha simétrica en rojo, negro y oro; con cada golpe se hace una lámina nueva.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['artistic', 'hypnotic', 'surprising'],
  concepts: ['rorschach', 'paper fold', 'ink', 'symmetry'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 4),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xfff3ead8, 0xff120608, 0xffd0141e, 0xffffb21a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta cambia de forma sin parar: a 60 FPS es fluido.
  framesPerSecond: 30, // energía: 60 no cabe; ver energy/frame_rate_record.json
);
