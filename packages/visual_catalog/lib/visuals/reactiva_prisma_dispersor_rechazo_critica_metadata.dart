import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_prisma_dispersor_rechazo_critica',
  name: 'Reactiva · Prisma Dispersor (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Con el golpe un haz blanco finísimo llega a un punto de la escena y se abre en abanico el espectro saturado, quemado junto al punto y cayendo con la distancia; el abanico se abre, gira un poco y se cierra. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['dramatic', 'colorful', 'elegant'],
  concepts: ['aparición momentánea', 'prism', 'dispersion', 'spectrum'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff2a10, 0xff30ff70, 0xff4a5bff],
  images: {'noise': 'assets/images/reactiva_quemado.png'},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
