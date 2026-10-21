import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_estrella_difraccion',
  name: 'Reactiva · Estrella de Difracción',
  publication: CreatorPublication.draft,
  description:
      'Con la caja se abre en un punto alto la estrella que hace una lente ante una luz fuerte: núcleo diminuto, picos larguísimos con el color separado y anillos de Airy, y se apaga en 300 ms. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['elegant', 'bright', 'rhythmic'],
  concepts: ['aparición momentánea', 'diffraction spikes', 'starburst', 'optics'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.6),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff3b2a, 0xffffc84a, 0xff6a8bff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece un instante con su momento.
  // Degradados, trazos y puntos agrupados: sin shaders por píxel.
  framesPerSecond: 30,
);
