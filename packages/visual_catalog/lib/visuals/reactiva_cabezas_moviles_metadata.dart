import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_cabezas_moviles',
  name: 'Reactiva · Mirada de Cabezas Móviles',
  publication: CreatorPublication.draft,
  description:
      'Con la caja, varios haces de cabezas móviles giran y apuntan a cámara: cada uno se vuelve un disco cegador con estrella de seis puntas, la escena se vela un instante y los haces se retiran. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['energetic', 'dramatic', 'warm'],
  concepts: ['aparición momentánea', 'moving heads', 'beam', 'concert lighting'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.68),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffe0161a, 0xffffa02a, 0xfffff4e6],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece un instante con su momento.
  // Degradados, trazos y puntos agrupados: sin shaders por píxel.
  framesPerSecond: 30,
);
