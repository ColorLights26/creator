import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_relampago_campo',
  name: 'Reactiva Mejorada · Relámpago Fuera de Campo',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. No se ve el rayo: en el golpe grande entra rasante desde una esquina la luz azul blanca de una tormenta fuera de plano, con golpe principal, segundo rayo y una cola que titila entre nubes. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['dramatic', 'dark', 'cinematic'],
  concepts: ['aparición momentánea', 'lightning', 'storm', 'off-screen light'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.08),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff4b2bff, 0xff9ec0ff, 0xfff2f6ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece un instante con su momento.
  // Degradados, trazos y puntos agrupados: sin shaders por píxel.
  framesPerSecond: 30,
);
