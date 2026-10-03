import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'bola_discoteca_2',
  name: 'Bola de Discoteca 2',
  publication: CreatorPublication.draft,
  description:
      'Bola de espejos en rojo intenso que gira y llena la sala de reflejos y haces rojos que estallan con cada golpe.',
  purposes: ['party', 'club', 'visualizer'],
  moods: ['festive', 'glamorous', 'energetic'],
  concepts: ['disco ball', 'mirror', 'reflections', 'party'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff070000, 0xffff1a1a, 0xffff4d1a, 0xffffb3b3],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Giro continuo y destellos: a 60 FPS la bola gira con fluidez.
  framesPerSecond: 60,
);
