import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_barrido_holografico',
  name: 'Reactiva Mejorada · Barrido Holográfico',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Al empezar una frase cruza en diagonal una banda iridiscente, como al inclinar una carta holográfica: interferencia arcoíris, retícula fina, línea especular y purpurina. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['futuristic', 'elegant', 'vivid'],
  concepts: ['aparición momentánea', 'holographic', 'iridescent', 'light sweep'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.3),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff3a5a, 0xffffb03a, 0xfff4f0ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece un instante con su momento.
  // Degradados, trazos y puntos agrupados: sin shaders por píxel.
  framesPerSecond: 30,
);
