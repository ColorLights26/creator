import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'kandinsky',
  name: 'Kandinsky Sinestesia',
  publication: CreatorPublication.draft,
  description:
      'Un cuadro de Kandinsky que se pinta con la música: los graves hacen círculos con halos, los medios triángulos y arcos, los agudos líneas y puntos, alrededor de un gran círculo que late.',
  purposes: ['visualizer', 'focus', 'party'],
  moods: ['artistic', 'playful', 'vibrant'],
  concepts: ['kandinsky', 'synesthesia', 'abstract art', 'composition'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 6),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xfff0e6d0, 0xffd7261e, 0xfff2b705, 0xff1d4e9e],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las formas aparecen con rebote: a 60 FPS es fluido.
  framesPerSecond: 30, // energía: ver energy/frame_rate_record.json
);
