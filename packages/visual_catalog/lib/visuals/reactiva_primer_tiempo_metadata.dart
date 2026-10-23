import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_primer_tiempo',
  name: 'Reactiva · Primer Tiempo',
  publication: CreatorPublication.draft,
  description:
      'Sólo en el primer pulso de cada compás la escena respira una vez, lenta: baja la luz sin color y vuelve en medio segundo, primero en el centro, o se abre una luz cálida desde el centro que se apaga encogiéndose. Marca el ritmo sin parpadear en cada golpe. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['minimal', 'rhythmic', 'calm'],
  concepts: ['aparición momentánea', 'downbeat', 'pulse', 'breathing light'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff000000, 0xffffc27a, 0xfffff7ea],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
