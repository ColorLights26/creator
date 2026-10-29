import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_onda_choque_espectral',
  name: 'Reactiva Mejorada · Onda de Choque Espectral',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. En el golpe grande cruza la pantalla un frente de luz gigante que nace fuera del cuadro: cresta blanca nítida con el azul adelantado y el rojo y ámbar rezagados, estela ámbar que se apaga enseguida y un eco más débil. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['energetic', 'dramatic', 'futuristic'],
  concepts: ['aparición momentánea', 'shockwave', 'chromatic aberration', 'light front'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff2a1a, 0xffffb21a, 0xff4a6bff],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
