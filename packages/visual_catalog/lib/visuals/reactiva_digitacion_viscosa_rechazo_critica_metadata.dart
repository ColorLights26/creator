import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_digitacion_viscosa_rechazo_critica',
  name: 'Reactiva · Digitación Viscosa (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Con el golpe un líquido de luz azul eléctrico se inyecta en un punto y avanza abriéndose en dedos que se parten por la punta, con el frente brillante, como en una celda de Hele-Shaw; al final se recoge hacia el punto. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['fluid', 'organic', 'cool'],
  concepts: ['aparición momentánea', 'viscous fingering', 'hele-shaw', 'fluid instability'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff1a2aff, 0xff3a7aff, 0xffe8f0ff],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
