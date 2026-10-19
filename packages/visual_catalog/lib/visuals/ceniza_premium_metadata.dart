import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'ceniza_premium',
  name: 'Ceniza Premium',
  publication: CreatorPublication.draft,
  description:
      'Ceniza que cae lenta y aletea entre un humo tenue, con motas que todavía arden en naranja y parpadean con su halo. Sin fondo, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['dark', 'cinematic', 'melancholic'],
  concepts: ['ash', 'embers', 'smoke', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff4a4644, 0xff9a948d, 0xffff6a10],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas simuladas con física: fluidas a 30 FPS en el móvil.
  framesPerSecond: 30,
);
