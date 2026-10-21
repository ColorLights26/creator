import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_onda_choque_espectral',
  name: 'Reactiva · Onda de Choque Espectral',
  publication: CreatorPublication.draft,
  description:
      'En el golpe grande cruza la pantalla un frente de luz gigante que nace fuera del cuadro, con cresta blanca, bordes rojo, ámbar y azul separados, estela ámbar y un eco. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['dramatic', 'energetic', 'futuristic'],
  concepts: ['aparición momentánea', 'shockwave', 'chromatic aberration', 'impact'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.2),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff2a1a, 0xffffb21a, 0xff4a6bff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece un instante con su momento.
  // Degradados, trazos y puntos agrupados: sin shaders por píxel.
  framesPerSecond: 30,
);
