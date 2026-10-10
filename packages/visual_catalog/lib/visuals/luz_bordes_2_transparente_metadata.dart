import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'luz_bordes_2_transparente',
  name: 'Luz de Bordes 2 Transparente',
  publication: CreatorPublication.draft,
  description:
      'Llamaradas de luz que nacen en los bordes y se extienden hacia el centro con la música; cada golpe lanza una onda que cruza la pantalla sobre fondo transparente.',
  purposes: ['visualizer', 'party', 'ambient'],
  moods: ['modern', 'vivid', 'minimal'],
  concepts: ['edge lighting', 'glow', 'spectrum', 'border'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffff5e3a, 0xffd14bff, 0xff3dc8ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // El brillo corre por el borde sin parar: a 60 FPS es fluido.
  framesPerSecond: 30,
);
