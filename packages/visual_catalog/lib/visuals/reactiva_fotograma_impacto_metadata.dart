import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_fotograma_impacto',
  name: 'Reactiva · Fotograma de Impacto',
  publication: CreatorPublication.draft,
  description:
      'El impact frame del anime en el golpe grande: dos cuadros en que la pantalla se hunde en negro y decenas de cuñas blancas apuntan a un foco, y luego se vuelven bermellón y se retiran. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['dramatic', 'intense', 'graphic'],
  concepts: ['aparición momentánea', 'impact frame', 'anime', 'speed lines'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.04),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff3a12, 0xffffd23a, 0xfffff6ea],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece un instante con su momento.
  // Degradados, trazos y puntos agrupados: sin shaders por píxel.
  framesPerSecond: 30,
);
