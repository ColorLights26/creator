import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_canon_seguimiento',
  name: 'Reactiva · Cañón de Seguimiento',
  publication: CreatorPublication.draft,
  description:
      'Tras una pausa, en el primer golpe se abre en cuatro cuadros el iris de doce láminas de un cañón de seguimiento: círculo de luz blanca cálida con caída suave, filo azul de la lente, polvo en la luz y el haz entre el humo; fuera la escena se oscurece y el iris se cierra. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['dramatic', 'theatrical', 'warm'],
  concepts: ['aparición momentánea', 'follow spot', 'iris', 'stage lighting', 'spotlight'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff000000, 0xff3d7bff, 0xfffff0d9],
  images: {'smoke': 'assets/images/reactiva_humo.png'},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
