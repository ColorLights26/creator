import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_latido_completo',
  name: 'Reactiva Mejorada · Latido Completo',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Una reacción por sonido: el bombo baja la luz a fondo y la devuelve suave desde el centro, la caja abre un destello cálido pequeño que se apaga encogiéndose y el golpe grande lanza el reflejo de un vidrio que cruza la escena. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['energetic', 'rhythmic', 'elegant'],
  concepts: ['aparición momentánea', 'sidechain', 'flash', 'glass reflection'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff000000, 0xffffc27a, 0xfffff7ea],
  images: {'dirt': 'assets/images/reactiva_suciedad_lente.png'},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
