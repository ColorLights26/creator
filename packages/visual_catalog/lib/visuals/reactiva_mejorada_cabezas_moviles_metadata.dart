import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_cabezas_moviles',
  name: 'Reactiva Mejorada · Mirada de Cabezas Móviles',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con la caja, cabezas móviles de haz estrecho escondidas abajo barren el humo con haces de núcleo blanco y halo de color y giran hasta mirar a cámara: la lente se vuelve un disco nítido con estrella de seis puntas y florece dos cuadros; luego se retiran. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['energetic', 'dramatic', 'vivid'],
  concepts: ['aparición momentánea', 'moving heads', 'beam', 'concert lighting', 'lens glare'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.2),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff1a2e, 0xffffb000, 0xfffff4e6],
  images: {'smoke': 'assets/images/reactiva_humo.png'},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
