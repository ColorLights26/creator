import 'package:scene_compositor/authoring.dart';

// Datos del visual. El código se encuentra en el archivo del mismo nombre
// sin el sufijo _metadata. ID único; aparece en Studio. Color Lights exige revisión.
const metadata = CreatorVisualMetadata(
  id: 'quiet_orbits',
  name: 'Órbitas · sin música',
  publication: CreatorPublication.draft,
  description:
      'Sistema orbital elegante con estela luminosa, calibrado para relajación.',
  purposes: ['relax', 'focus', 'sleep'],
  moods: ['calm', 'meditative'],
  concepts: ['orbits', 'space', 'light', 'planets'],
  credits: CreatorCredits(
    author: 'Chic Apps',
    license: 'Proprietary',
    source: 'Visual Studio examples',
  ),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.none,
  colors: [0xff03040a, 0xff233c66, 0xff7fb8ff, 0xffd9e6ff],
  controls: CreatorControls(speed: .5, glow: .8),
);
