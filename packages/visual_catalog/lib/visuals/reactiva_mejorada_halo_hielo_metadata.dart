import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_halo_hielo',
  name: 'Reactiva Mejorada · Halo de Hielo',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Al empezar una frase se enciende un halo de 22° alrededor de una luz: borde interior rojizo, parhelios, arco tangente en ala de gaviota y polvo de diamante. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['magical', 'elegant', 'cold'],
  concepts: ['aparición momentánea', 'ice halo', 'sun dogs', 'atmospheric optics'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.3),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff4a2a, 0xffffa040, 0xffeaf2ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece un instante con su momento.
  // Degradados, trazos y puntos agrupados: sin shaders por píxel.
  framesPerSecond: 30,
);
