import 'package:scene_compositor/authoring.dart';

// Datos del visual. El código se encuentra en el archivo del mismo nombre
// sin el sufijo _metadata. ID único; aparece en Studio. Color Lights exige revisión.
const metadata = CreatorVisualMetadata(
  id: 'liquid_gold',
  name: 'Oro líquido',
  publication: CreatorPublication.draft,
  description:
      'Seda de oro fundido que fluye con brillos chispeantes al ritmo.',
  purposes: ['relax', 'ambient', 'decor'],
  moods: ['elegant', 'warm', 'dreamy'],
  concepts: ['gold', 'silk', 'liquid', 'luxury'],
  credits: CreatorCredits(
    author: 'Chic Apps',
    license: 'Proprietary',
    source: 'Creator Studio collection',
  ),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff140b02, 0xffa06a14, 0xfff0b542, 0xfffff1cf],
  controls: CreatorControls(intensity: 1, speed: .5, detail: 1, glow: .75),
);
