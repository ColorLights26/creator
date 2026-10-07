import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'eco_infinito',
  name: 'Eco Infinito',
  publication: CreatorPublication.draft,
  description:
      'Al estilo del clásico MilkDrop de Winamp: la forma de la música deja ecos de arcoíris que giran y se hunden hacia el infinito, cada uno con lo que sonó un instante antes.',
  purposes: ['visualizer', 'party', 'club'],
  moods: ['psychedelic', 'retro', 'hypnotic'],
  concepts: ['milkdrop', 'feedback', 'echo', 'spectrum'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff020005, 0xffff1f4f, 0xffffc400, 0xff00e676],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Los ecos se hunden de forma continua: a 60 FPS es fluido.
  framesPerSecond: 30, // energía: 60 no cabe; ver energy/frame_rate_record.json
);
