import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_fotograma_impacto',
  name: 'Reactiva Mejorada · Fotograma de Impacto',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. El impact frame del anime en el golpe grande: dos cuadros en que la escena se hunde en negro y decenas de cuñas blancas finas apuntan a un foco; luego se vuelven bermellón con borde dorado y se retiran hacia los bordes. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['energetic', 'dramatic', 'graphic'],
  concepts: ['aparición momentánea', 'impact frame', 'anime', 'speed lines'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff3a12, 0xffffd23a, 0xfffff6ea],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
