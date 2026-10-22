import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_celuloide_quemado',
  name: 'Reactiva · Celuloide Quemado',
  publication: CreatorPublication.draft,
  description:
      'La película se quema desde una esquina o un borde, con varios focos que se unen: un frente de lóbulos y dedos finos quema a blanco y pasa a amarillo, naranja y rojo, con ampollas que destellan y chispas; lo quemado se aclara enseguida y queda un anillo de fuego que avanza. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['dramatic', 'vintage', 'warm'],
  concepts: ['aparición momentánea', 'film burn', 'celluloid', '16mm'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffe01e00, 0xffff7a00, 0xffffe45c],
  images: {'burn': 'assets/images/reactiva_quemado.png'},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
