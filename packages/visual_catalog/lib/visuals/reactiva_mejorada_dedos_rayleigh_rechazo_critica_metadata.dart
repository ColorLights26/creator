import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_dedos_rayleigh_rechazo_critica',
  name: 'Reactiva Mejorada · Dedos de Rayleigh (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con el golpe una capa de tinte luminoso se descuelga desde arriba en dedos que caen cada vez más deprisa y se ensanchan en cabezas que se enrollan, como en la inestabilidad de Rayleigh-Taylor; carmesí y magenta. Luego se despegan y se deshacen. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['strange', 'fluid', 'warm'],
  concepts: ['aparición momentánea', 'rayleigh taylor', 'fluid instability', 'ink fingers'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff0a28, 0xffff1068, 0xffff40b0],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
