import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_fuga_carrete',
  name: 'Reactiva · Fuga de Luz de Carrete',
  publication: CreatorPublication.draft,
  description:
      'Al empezar una frase entra desde un borde una fuga de luz de cámara de película: lóbulos orgánicos que se deslizan, respiran y se van, amarillo blanco junto al borde, naranja y rojo vivo hacia dentro, con grano y un leve parpadeo. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['warm', 'nostalgic', 'dreamy'],
  concepts: ['aparición momentánea', 'light leak', 'film', 'super 8', 'grain'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.2),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff3b1f, 0xffff8a00, 0xffffe8b0],
  images: {'noise': 'assets/images/reactiva_quemado.png'},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
