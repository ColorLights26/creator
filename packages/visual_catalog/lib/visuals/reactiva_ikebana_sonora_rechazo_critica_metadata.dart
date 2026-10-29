import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_ikebana_sonora_rechazo_critica',
  name: 'Reactiva · Ikebana Sonora (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Con el golpe, como si el sonido lanzara pintura desde un altavoz, salen disparadas lenguas de pintura de luz roja, amarilla y violeta que suben en arco a cámara lenta, se rizan y acaban en gotas con brillo húmedo; al caer se adelgazan y se recogen. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['dynamic', 'artistic', 'bold'],
  concepts: ['aparición momentánea', 'sound of ikebana', 'paint splash', 'high speed'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff1a20, 0xffffb000, 0xff7a20ff],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
