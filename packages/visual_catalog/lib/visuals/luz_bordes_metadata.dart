import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'luz_bordes',
  name: 'Luz de Bordes',
  publication: CreatorPublication.draft,
  description:
      'Resplandor de colores que recorre los bordes de la pantalla y se engrosa con cada banda de la música, con pulsos que corren con el ritmo.',
  purposes: ['visualizer', 'party', 'ambient'],
  moods: ['modern', 'vivid', 'minimal'],
  concepts: ['edge lighting', 'glow', 'spectrum', 'border'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff000000, 0xffff5e3a, 0xffd14bff, 0xff3dc8ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // El brillo corre por el borde sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
