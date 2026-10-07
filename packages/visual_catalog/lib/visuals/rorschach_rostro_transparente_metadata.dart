import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'rorschach_rostro_transparente',
  name: 'Rorschach Rostro Transparente',
  publication: CreatorPublication.draft,
  description:
      'Una mancha de Rorschach que resulta ser una cara: dos ojos que te miran y parpadean, una boca que se abre con los graves y pupilas que se dilatan con cada golpe. Sin fondo: se ve lo que hay detrás.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['disturbing', 'mysterious', 'creepy'],
  concepts: ['rorschach', 'pareidolia', 'face', 'eyes'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff0a0505, 0xffb0000c, 0xffff3a1a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta cambia de forma sin parar: a 60 FPS es fluido.
  framesPerSecond: 30, // energía: ver energy/frame_rate_record.json
);
