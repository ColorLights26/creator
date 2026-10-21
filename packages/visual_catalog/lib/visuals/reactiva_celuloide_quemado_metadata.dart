import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_celuloide_quemado',
  name: 'Reactiva · Celuloide Quemado',
  publication: CreatorPublication.draft,
  description:
      'En el golpe grande la película se quema desde una esquina: una mancha irregular que hierve, con núcleo casi blanco, cuerpo naranja, borde granate, ampollas y grano, y se apaga enseguida. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['dramatic', 'vintage', 'warm'],
  concepts: ['aparición momentánea', 'film burn', 'celluloid', 'light leak'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.2),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffb3122e, 0xffff7a00, 0xffffe15a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece un instante con su momento.
  // Degradados, trazos y puntos agrupados: sin shaders por píxel.
  framesPerSecond: 30,
);
