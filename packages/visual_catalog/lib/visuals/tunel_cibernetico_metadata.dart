import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'tunel_cibernetico',
  name: 'Túnel Cibernético',
  publication: CreatorPublication.draft,
  description:
      'Túnel futurista de bloques azules y rojos con polígonos de neón, orbes en los vértices, láseres cian y chispas doradas que pasan volando.',
  purposes: ['party', 'club', 'gaming'],
  moods: ['futuristic', 'intense', 'epic'],
  concepts: ['cyber tunnel', 'neon polygon', 'lasers', 'vj loop'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff01020a, 0xff2b3cff, 0xffff1f3d, 0xff3df2ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Avance continuo: a 60 FPS el túnel es fluido.
  framesPerSecond: 30, // energía: 60 no cabe; ver energy/frame_rate_record.json
);
