import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_borde_luz',
  name: 'Reactiva Mejorada · Borde de Luz',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con los platillos entra por un borde la luz de un foco justo fuera del cuadro: quema a blanco junto al borde, se abre a ámbar y cae a rojo vivo con caída suave, sin llegar al centro. Cada golpe entra por un sitio distinto. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['warm', 'cinematic', 'energetic'],
  concepts: ['aparición momentánea', 'edge light', 'backlight', 'light spill'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff2a10, 0xffffa020, 0xfffff4e0],
  images: {'noise': 'assets/images/reactiva_quemado.png'},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
