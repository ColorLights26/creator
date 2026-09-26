import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'furia_estelar',
  name: 'Furia Estelar',
  publication: CreatorPublication.draft,
  description:
      'Supernova viva y fulguraciones solares con arcos magnéticos coronales y convección nuclear que estallan al ritmo de la música.',
  purposes: ['party', 'rave', 'visualizer', 'energy'],
  moods: ['epic', 'intense', 'blazing', 'powerful'],
  concepts: ['supernova', 'solar_flare', 'sun', 'plasma', 'coronal_mass_ejection'],
  credits: CreatorCredits(
    author: 'Color Lights 26',
    license: 'Proprietary',
    source: 'Color Lights Studio',
  ),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.0),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xFF050000, 0xFFFF2200, 0xFFFF9900, 0xFFFFFFEE],
  controls: CreatorControls(intensity: 1.0, speed: 1.0, detail: 1.0, glow: 1.3),
);
