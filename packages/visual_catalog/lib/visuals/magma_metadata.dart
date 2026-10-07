import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'magma',
  name: 'Magma',
  publication: CreatorPublication.draft,
  description:
      'Corteza volcánica negra con grietas de lava naranja que se abren con los graves, roca fundida que fluye debajo y brasas que saltan con cada golpe.',
  purposes: ['visualizer', 'party', 'relax'],
  moods: ['intense', 'warm', 'epic'],
  concepts: ['lava', 'magma', 'cracks', 'embers'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff050100, 0xffd41a00, 0xffff7a00, 0xffffd24a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La lava fluye sin parar: a 60 FPS es fluido.
  framesPerSecond: 30, // energía: 60 no cabe; ver energy/frame_rate_record.json
);
