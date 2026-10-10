import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'lampara_lava',
  name: 'Lámpara de Lava',
  publication: CreatorPublication.draft,
  description:
      'Gotas brillantes de cera roja y naranja que suben, se estiran y se fusionan dentro de un líquido violeta; los graves las calientan y cada golpe las hace temblar.',
  purposes: ['visualizer', 'relax', 'party'],
  moods: ['retro', 'warm', 'liquid'],
  concepts: ['lava lamp', 'metaballs', 'wax', 'liquid'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 4),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff14001f, 0xffff2a00, 0xffff8a00, 0xffffe066],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La cera se mueve despacio pero sin saltos: a 60 FPS es fluido.
  framesPerSecond: 30,
);
