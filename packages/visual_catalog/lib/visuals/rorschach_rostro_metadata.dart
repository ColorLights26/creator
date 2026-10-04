import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'rorschach_rostro',
  name: 'Rorschach Rostro',
  publication: CreatorPublication.draft,
  description:
      'Una mancha de Rorschach que resulta ser una cara: dos ojos que te miran y parpadean, una boca que se abre con los graves y pupilas que se dilatan con cada golpe.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['disturbing', 'mysterious', 'creepy'],
  concepts: ['rorschach', 'pareidolia', 'face', 'eyes'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xffece2cc, 0xff0a0505, 0xffb0000c, 0xffff3a1a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta cambia de forma sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
