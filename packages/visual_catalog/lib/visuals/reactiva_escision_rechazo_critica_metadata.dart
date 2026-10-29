import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_escision_rechazo_critica',
  name: 'Reactiva · Escisión (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Con el golpe aparece una lámina de luz amarilla que se parte en dos capas, bermellón y lima, que se despegan por caminos curvos opuestos; el amarillo de donde se tapan se encoge y cada capa se adelgaza desde su borde lejano. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['bold', 'graphic', 'warm'],
  concepts: ['aparición momentánea', 'additive split', 'layer peel', 'misregistration'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff3008, 0xff9cff14, 0xfffff6e0],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
