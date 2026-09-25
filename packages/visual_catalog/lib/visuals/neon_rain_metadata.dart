import 'package:scene_compositor/authoring.dart';

// Datos del visual. El código se encuentra en el archivo del mismo nombre
// sin el sufijo _metadata. ID único; aparece en Studio. Color Lights exige revisión.
const metadata = CreatorVisualMetadata(
  id: 'neon_rain',
  name: 'Lluvia de neón',
  publication: CreatorPublication.draft,
  description:
      'Capa transparente de lluvia luminosa con destellos de ciudad al fondo.',
  purposes: ['ambient', 'decor', 'sleep'],
  moods: ['mysterious', 'calm'],
  concepts: ['rain', 'neon', 'overlay', 'city'],
  credits: CreatorCredits(
    author: 'Chic Apps',
    license: 'Proprietary',
    source: 'Creator Studio collection',
  ),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0xff0a0f1e, 0xff3fe0ff, 0xffa06bff, 0xffeafcff],
  controls: CreatorControls(intensity: .9, speed: .55, detail: 1.15, glow: .9),
);
