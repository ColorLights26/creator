import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_tajo_luz_rechazo_critica',
  name: 'Reactiva Mejorada · Tajo de Luz (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con el golpe un tajo de luz corta la escena en media luna: un arco que se traza en un parpadeo, filo blanco nítido, cuerpo carmesí que se desvanece hacia dentro, líneas de velocidad y chispas al final; luego adelgaza hasta desaparecer. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['energetic', 'dramatic', 'intense'],
  concepts: ['aparición momentánea', 'slash', 'crescent', 'speed lines'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff1040, 0xffff5a20, 0xfffff4ee],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
