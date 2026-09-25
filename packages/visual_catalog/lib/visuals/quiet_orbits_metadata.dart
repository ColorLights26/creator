import 'package:scene_compositor/authoring.dart';

// Datos del visual. El código se encuentra en el archivo del mismo nombre
// sin el sufijo _metadata. ID único; aparece en Studio. Color Lights exige revisión.
const metadata = CreatorVisualMetadata(
  id: 'quiet_orbits',
  name: 'Órbitas · sin música',
  publication: CreatorPublication.draft,
  description:
      'Órbitas luminosas de movimiento continuo, independientes del audio.',
  purposes: ['relax', 'focus'],
  moods: ['calm', 'meditative'],
  concepts: ['orbits', 'space', 'light'],
  credits: CreatorCredits(
    author: 'Chic Apps',
    license: 'Proprietary',
    source: 'Visual Studio examples',
  ),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.none,
  colors: [0xff080b15, 0xff63bfd6, 0xffae79d9, 0xffffcfac],
  controls: CreatorControls(speed: .5, glow: .8),
);
