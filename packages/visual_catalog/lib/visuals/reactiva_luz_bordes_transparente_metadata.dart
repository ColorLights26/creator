import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_luz_bordes_transparente',
  name: 'Reactiva · Luz de Bordes',
  publication: CreatorPublication.draft,
  description:
      'Versión reactiva: sin música no dibuja nada y sólo aparece un instante con el golpe grande (o el momento que elijas en Ajustes) y desaparece. Resplandor de colores que recorre los bordes de la pantalla y se engrosa con cada banda de la música, con pulsos que corren con el ritmo sobre fondo transparente.',
  purposes: ['visualizer', 'party', 'ambient'],
  moods: ['modern', 'vivid', 'minimal'],
  concepts: ['aparición momentánea', 'edge lighting', 'glow', 'spectrum', 'border'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.2),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff5e3a, 0xffd14bff, 0xff3dc8ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // El brillo corre por el borde sin parar: a 60 FPS es fluido.
  framesPerSecond: 30,
);
