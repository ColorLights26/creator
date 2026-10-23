import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_aire_relieve_rechazo_critica',
  name: 'Reactiva Mejorada · Aire en Relieve (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con el golpe una bocanada de aire caliente se enciende en relieve esmeralda y violeta; sus remolinos grandes se parten en otros cada vez más pequeños de un extremo al otro y se apaga al afinarse. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['strange', 'fluid', 'graphic'],
  concepts: ['aparición momentánea', 'color schlieren', 'turbulent cascade', 'refraction'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff08ff70, 0xff9a14ff, 0xfff6f0ff],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
