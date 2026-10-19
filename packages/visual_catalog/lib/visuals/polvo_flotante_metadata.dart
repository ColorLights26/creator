import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'polvo_flotante',
  name: 'Polvo Flotante',
  publication: CreatorPublication.draft,
  description:
      'Capa transparente de polvo luminoso: muchas motas blancas diminutas que flotan a la deriva y titilan, algunas más cerca y desenfocadas, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['calm', 'dreamy', 'elegant'],
  concepts: ['dust', 'floating particles', 'space', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff8a93a8, 0xffdfe3ec, 0xffffffff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas sencillas: a 30 FPS gastan poca batería.
  framesPerSecond: 30,
);
