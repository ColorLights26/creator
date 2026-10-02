import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'tormenta_electrica',
  name: 'Tormenta Eléctrica',
  publication: CreatorPublication.draft,
  description:
      'Cielo de tormenta donde cada golpe dispara un rayo que ilumina las nubes desde dentro y se refleja en el suelo mojado.',
  purposes: ['party', 'visualizer'],
  moods: ['dramatic', 'dark', 'epic'],
  concepts: ['storm', 'lightning', 'clouds', 'rain'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff03040a, 0xff18213f, 0xff7c74ff, 0xffdcd2ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
