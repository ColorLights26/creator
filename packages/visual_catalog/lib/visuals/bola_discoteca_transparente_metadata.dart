import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'bola_discoteca_transparente',
  name: 'Bola de Discoteca Transparente',
  publication: CreatorPublication.draft,
  description:
      'Bola de espejos que gira y lanza cientos de puntos de luz dorada, rosa y plateada que barren la sala al ritmo de la música sobre fondo transparente.',
  purposes: ['party', 'club', 'visualizer'],
  moods: ['festive', 'glamorous', 'energetic'],
  concepts: ['disco ball', 'mirror', 'reflections', 'party'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffffc46b, 0xffff6fae, 0xffe8ecff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Giro continuo y destellos: a 60 FPS la bola gira con fluidez.
  framesPerSecond: 30, // energía: 60 no cabe; ver energy/frame_rate_record.json
);
