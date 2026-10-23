import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_purpurina_rafaga',
  name: 'Reactiva Mejorada · Purpurina en Ráfaga',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con los platillos una onda de luz recorre miles de microfacetas que destellan sólo cuando su ángulo coincide, como lentejuelas bajo un foco: cada una en su color y las más fuertes con una cruz fina de cuatro puntas. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['glamorous', 'sparkly', 'energetic'],
  concepts: ['aparición momentánea', 'glitter', 'sequins', 'sparkle', 'specular'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff3a5a, 0xffffc23a, 0xff5a8aff],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
