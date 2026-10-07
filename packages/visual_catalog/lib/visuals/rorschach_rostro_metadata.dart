import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'rorschach_rostro',
  name: 'Rorschach Rostro',
  publication: CreatorPublication.draft,
  description:
      'Una mancha de Rorschach en la que a veces se ve una cara: ojos que se abren y parpadean, una boca que grita con cada golpe; la cara cambia de expresión con cada forma nueva y se disuelve otra vez.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['eerie', 'surreal', 'disturbing'],
  concepts: ['rorschach', 'pareidolia', 'face', 'inkblot'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 4),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xffe7dcc8, 0xff0b0706, 0xffa8101a, 0xfffff4e6],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta cambia de forma sin parar: a 60 FPS es fluido.
  framesPerSecond: 30, // energía: 60 no cabe; ver energy/frame_rate_record.json
);
