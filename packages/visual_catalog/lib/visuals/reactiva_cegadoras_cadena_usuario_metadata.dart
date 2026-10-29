import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_cegadoras_cadena_usuario',
  name: 'Reactiva · Cegadoras en Cadena (pasada por mí)',
  publication: CreatorPublication.draft,
  description:
      'Módulos grandes de cuatro cegadoras en dos filas se encienden en cadena: cada lámpara quema a blanco en su centro con resplandores suaves y una estrella de seis puntas; el brillo cae en unos cuadros y queda el filamento, que se enfría de ámbar a naranja y rojo brasa. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['dramatic', 'energetic', 'warm'],
  concepts: ['aparición momentánea', 'audience blinders', 'concert lighting', 'tungsten', 'diffraction star'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.1),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffb01800, 0xffff5a1a, 0xfffff6e8],
  images: {'smoke': 'assets/images/reactiva_humo.png'},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
