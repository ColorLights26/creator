import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_acuarela_florece_rechazo_critica',
  name: 'Reactiva Mejorada · Acuarela que Florece (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con el golpe caen dos gotas de pigmento de luz, magenta y amarillo limón, que se abren como acuarela en papel mojado: bordes plumosos que se ramifican, grano por dentro y rojo coral donde se funden; al secarse se pierden en grano. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['fluid', 'artistic', 'dreamy'],
  concepts: ['aparición momentánea', 'watercolor', 'wet on wet', 'pigment bloom'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff10a0, 0xffffd010, 0xfffff8f0],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
