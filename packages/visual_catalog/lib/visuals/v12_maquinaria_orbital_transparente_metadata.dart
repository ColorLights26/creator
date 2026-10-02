import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'v12_maquinaria_orbital_transparente',
  name: 'Maquinaria Orbital Transparente',
  publication: CreatorPublication.draft,
  description: 'Astrolabio astronómico transparente de relojería en latón, engranajes móviles, órbitas y planetas.',
  purposes: ['hud', 'ambient'],
  moods: ['steampunk', 'celestial'],
  concepts: ['clockwork', 'astrolabe', 'planets'],
  credits: CreatorCredits(author: 'Visuales Inmersivas v12 (Overlay)'),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0xffe5a952, 0xff70c0c0, 0xffffffff, 0xff402810],
  controls: CreatorControls(intensity: 1.0, speed: 1.0, detail: 1.0, glow: 1.0),
);
