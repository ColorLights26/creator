import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_duendes_rojos_rechazo_critica',
  name: 'Reactiva Mejorada · Duendes Rojos (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con el golpe estallan en medio de la escena unos duendes rojos: columnas de luz carmesí difusa de distintos tamaños que se deshilachan hacia abajo en zarcillos que acaban en azul violeta; se recogen hacia arriba y se desvanecen. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['strange', 'dramatic', 'electric'],
  concepts: ['aparición momentánea', 'red sprites', 'upper atmosphere', 'discharge'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff0a20, 0xffff3a50, 0xff3a2aff],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
