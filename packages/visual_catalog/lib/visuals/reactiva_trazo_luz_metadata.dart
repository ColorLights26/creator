import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_trazo_luz',
  name: 'Reactiva · Trazo de Luz (aprobada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Con el golpe una luz pinta en el aire un trazo caligráfico con un bucle, como en el light painting: cabeza quemada, trazo que sigue encendido y cambia de grosor con la dirección, blanco, oro, naranja y rojo; luego la cola se recoge. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['energetic', 'warm', 'graphic'],
  concepts: ['aparición momentánea', 'light painting', 'long exposure', 'calligraphy'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff2a10, 0xffff8a1a, 0xfffff4e0],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
