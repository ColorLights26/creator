import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_halo_hielo',
  name: 'Reactiva Mejorada · Halo de Hielo',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Al empezar una frase se enciende el halo de 22° alrededor de una luz alta: borde interior rojo que pasa a naranja con cola blanca fría, arco tangente en ala de gaviota, parhelios con cara roja y cola blanca y polvo de diamante que titila; luego se rompe en pedazos. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['dreamy', 'elegant', 'cold'],
  concepts: ['aparición momentánea', 'ice halo', 'sundogs', 'diamond dust', 'atmospheric optics'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 0.6),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff2a10, 0xffff8a1a, 0xff9ab8ff],
  images: {'noise': 'assets/images/reactiva_quemado.png'},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
