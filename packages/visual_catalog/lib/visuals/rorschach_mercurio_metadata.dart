import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'rorschach_mercurio',
  name: 'Rorschach Mercurio',
  publication: CreatorPublication.draft,
  description:
      'Una mancha de Rorschach de mercurio negro: metal líquido que refleja un horizonte en llamas, cambia de forma salpicando gotas que salen disparadas y vuelven, y se ondula con cada golpe.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['luxurious', 'mysterious', 'fluid'],
  concepts: ['rorschach', 'liquid metal', 'chrome', 'mercury'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 4),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff050307, 0xff2a0806, 0xffff5a14, 0xfffff0d8],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta cambia de forma sin parar: a 60 FPS es fluido.
  framesPerSecond: 30, // energía: 60 no cabe; ver energy/frame_rate_record.json
);
