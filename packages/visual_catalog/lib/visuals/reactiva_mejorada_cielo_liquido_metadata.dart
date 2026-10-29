import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_cielo_liquido',
  name: 'Reactiva Mejorada · Cielo Líquido (aprobada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con el golpe se enciende por encima de la escena una lámina de láser rojo que corta el humo: un techo de olas de luz en perspectiva que ruedan hacia ti, con crestas rojas finas y un velo de humo encendido; se abre barriendo y se apaga adelgazando. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['club', 'dramatic', 'hypnotic'],
  concepts: ['aparición momentánea', 'liquid sky', 'laser sheet', 'haze'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff1a10, 0xffff5a30, 0xfffff0ea],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
