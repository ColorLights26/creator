import 'package:scene_compositor/authoring.dart';

// Datos del visual. El código se encuentra en el archivo del mismo nombre
// sin el sufijo _metadata. ID único; aparece en Studio. Color Lights exige revisión.
const metadata = CreatorVisualMetadata(
  id: 'prismatic_halo',
  name: 'Halo · capa de luz',
  publication: CreatorPublication.draft,
  description:
      'Anillo iridiscente con dispersión cromática y brillo que respira; capa sutil.',
  purposes: ['decor', 'visualizer', 'relax'],
  moods: ['elegant', 'dreamy'],
  concepts: ['halo', 'ring', 'iridescent', 'overlay'],
  credits: CreatorCredits(
    author: 'Chic Apps',
    license: 'Proprietary',
    source: 'Visual Studio examples',
  ),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0xff050508, 0xffff5d8f, 0xff67e9ff, 0xfffff3c8],
  controls: CreatorControls(intensity: 1, speed: .5, detail: 1, glow: .8),
);
