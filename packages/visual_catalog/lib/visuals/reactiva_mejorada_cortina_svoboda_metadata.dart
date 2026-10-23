import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_cortina_svoboda',
  name: 'Reactiva Mejorada · Cortina Svoboda',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Al empezar una frase se materializa desde arriba una cortina de decenas de haces finísimos casi blancos a distancias irregulares, con su lámpara caliente arriba, venas más intensas y polvo flotando; se mantiene un instante y se recoge hacia arriba. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['dramatic', 'theatrical', 'elegant'],
  concepts: ['aparición momentánea', 'light curtain', 'svoboda', 'beams', 'stage haze'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff4a1a, 0xffffb44a, 0xfffff4e0],
  images: {'smoke': 'assets/images/reactiva_humo.png'},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
