import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_reflejo_cruza',
  name: 'Reactiva · Reflejo que Cruza',
  publication: CreatorPublication.draft,
  description:
      'Al empezar un compás o una frase, el reflejo de un vidrio atraviesa la escena una vez: brillo ancho y suave, línea nítida en el centro y otra tenue detrás, filo irisado en los bordes y las huellas del cristal dentro del brillo. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['elegant', 'calm', 'premium'],
  concepts: ['aparición momentánea', 'glass reflection', 'sheen', 'sweep', 'specular'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff000000, 0xffffc27a, 0xfffff7ea],
  images: {'dirt': 'assets/images/reactiva_suciedad_lente.png'},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
