import 'package:scene_compositor/authoring.dart';

// Datos del visual. El código se encuentra en el archivo del mismo nombre
// sin el sufijo _metadata. ID único; aparece en Studio. Color Lights exige revisión.
const metadata = CreatorVisualMetadata(
  id: 'radial_spectrum',
  name: 'Radar · espectro',
  publication: CreatorPublication.draft,
  description:
      'Corona radial de barras que dibuja el espectro y late con el tempo.',
  purposes: ['visualizer', 'party'],
  moods: ['energetic', 'focused'],
  concepts: ['spectrum', 'radial', 'music', 'visualizer'],
  credits: CreatorCredits(
    author: 'Chic Apps',
    license: 'Proprietary',
    source: 'Creator Studio collection',
  ),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.music,
  colors: [0xff04060d, 0xff00e3a4, 0xff2f7bff, 0xffd46bff],
  controls: CreatorControls(intensity: 1, speed: .7, detail: 1, glow: .85),
);
