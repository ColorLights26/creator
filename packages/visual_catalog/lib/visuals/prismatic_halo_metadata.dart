import 'package:scene_compositor/authoring.dart';

// Datos del visual. El código se encuentra en el archivo del mismo nombre
// sin el sufijo _metadata. ID único; draft aparece en Studio y Color Lights debug.
const metadata = CreatorVisualMetadata(
  id: 'prismatic_halo',
  name: 'Halo · capa de luz',
  publication: CreatorPublication.draft,
  description:
      'Un halo de luz transparente que acompaña los acentos musicales.',
  purposes: ['visualizer', 'party'],
  moods: ['dreamy', 'energetic'],
  concepts: ['halo', 'prism', 'light'],
  credits: CreatorCredits(
    author: 'Chic Apps',
    license: 'Proprietary',
    source: 'Visual Studio examples',
  ),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0xff040712, 0xff49eadc, 0xffb17dff, 0xffffcddd],
  controls: CreatorControls(speed: .5, glow: .8),
);
