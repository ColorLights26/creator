import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_proyeccion_aceite_rechazo_critica',
  name: 'Reactiva · Proyección de Aceite (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Con el golpe florece una mancha de tintes de aceite (rojo, ámbar y violeta) con contornos vivos que fluyen y se montan unos sobre otros, como en los light shows de los 60; se recoge encogiendo y juntando las cadenas. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['psychedelic', 'fluid', 'warm'],
  concepts: ['aparición momentánea', 'liquid light show', 'oil projection', 'dye'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff2a10, 0xffffa020, 0xff4a2aff],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
