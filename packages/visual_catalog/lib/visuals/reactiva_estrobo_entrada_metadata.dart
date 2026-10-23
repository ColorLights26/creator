import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_estrobo_entrada',
  name: 'Reactiva · Estrobo de Entrada',
  publication: CreatorPublication.draft,
  description:
      'En el golpe grande, de uno a tres parpadeos de un estroboscopio colgado arriba en los pulsos siguientes, cada uno más débil: quemado en el borde superior y azul frío saturado al caer, a pleno en el mismo cuadro y apagado al segundo; o la escena baja de luz sin color. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['energetic', 'intense', 'club'],
  concepts: ['aparición momentánea', 'strobe', 'flash', 'drop'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff000000, 0xff6a9cff, 0xfff4f8ff],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
