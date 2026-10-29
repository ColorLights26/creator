import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_leche_magica_rechazo_critica',
  name: 'Reactiva · Leche Mágica (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Con el golpe una gota de jabón empuja hacia fuera gotas de tinte rojo, ámbar y azul eléctrico, que salen disparadas en vetas y lenguas dejando el centro limpio, como en la leche mágica; luego se adelgazan en hilos hasta desaparecer. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['fluid', 'playful', 'psychedelic'],
  concepts: ['aparición momentánea', 'magic milk', 'dye burst', 'marangoni'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff1a10, 0xffffa000, 0xff1a50ff],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
