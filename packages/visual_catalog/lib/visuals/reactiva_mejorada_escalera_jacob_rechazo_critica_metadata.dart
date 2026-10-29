import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_escalera_jacob_rechazo_critica',
  name: 'Reactiva Mejorada · Escalera de Jacob (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con el golpe salta un arco eléctrico con un fogonazo y sube como en una escalera de Jacob: se estira entre dos raíles invisibles, tiembla, lleva una llama naranja encima, deja peldaños de luz por debajo y arriba se rompe. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['electric', 'dramatic', 'strange'],
  concepts: ['aparición momentánea', 'jacobs ladder', 'electric arc', 'high voltage'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff6a20ff, 0xffff4a10, 0xfff6f0ff],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
