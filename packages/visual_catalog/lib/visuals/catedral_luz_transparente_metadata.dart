import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'catedral_luz_transparente',
  name: 'Catedral de Luz Transparente',
  publication: CreatorPublication.draft,
  description:
      'Haces volumétricos a través de un rosetón de vidrieras que se encienden con el espectro y estallan en cada golpe sobre fondo transparente.',
  purposes: ['relax', 'visualizer', 'party'],
  moods: ['epic', 'spiritual', 'cinematic'],
  concepts: ['god rays', 'stained glass', 'light', 'cathedral'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffff4a6e, 0xff3f7bff, 0xffffc766],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
