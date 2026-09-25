import 'package:scene_compositor/authoring.dart';

// Datos del visual. El código se encuentra en el archivo del mismo nombre
// sin el sufijo _metadata. ID único; aparece en Studio. Color Lights exige revisión.
const metadata = CreatorVisualMetadata(
  id: 'gold_dust',
  name: 'Polvo de oro',
  publication: CreatorPublication.draft,
  description:
      'Partículas doradas flotantes con destellos que titilan sobre tu fondo.',
  purposes: ['relax', 'ambient', 'decor'],
  moods: ['elegant', 'warm', 'dreamy'],
  concepts: ['gold', 'dust', 'bokeh', 'overlay'],
  credits: CreatorCredits(
    author: 'Chic Apps',
    license: 'Proprietary',
    source: 'Creator Studio collection',
  ),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0xff120c04, 0xffc08a20, 0xfff5c455, 0xfffff4d6],
  controls: CreatorControls(intensity: 1, speed: .5, detail: 1, glow: .9),
);
