import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'polvo_colores',
  name: 'Polvo de Colores',
  publication: CreatorPublication.draft,
  description:
      'Explosiones de polvo de colores en cámara súper lenta: cada golpe lanza una nube fucsia, mandarina o lima que se expande y se mezcla sobre negro.',
  purposes: ['party', 'visualizer', 'festival'],
  moods: ['explosive', 'vivid', 'epic'],
  concepts: ['powder', 'holi', 'explosion', 'clouds'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3.0),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff000000, 0xffff1f8e, 0xffff7a1a, 0xffa8f000],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Nubes que se expanden sin parar: a 60 FPS la cámara lenta es fluida.
  framesPerSecond: 30, // energía: ver energy/frame_rate_record.json
);
