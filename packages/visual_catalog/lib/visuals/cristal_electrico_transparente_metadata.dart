import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'cristal_electrico_transparente',
  name: 'Cristal Eléctrico Transparente',
  publication: CreatorPublication.draft,
  description:
      'Una figura de Lichtenberg, el rayo fractal que se quema en la madera, crece ramificándose al rojo vivo; cada golpe manda una descarga blanca que recorre todas sus ramas sobre fondo transparente.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['electric', 'organic', 'intense'],
  concepts: ['lichtenberg figure', 'fractal', 'lightning', 'growth'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffc81400, 0xffff7a00, 0xffffe680],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las ramas crecen paso a paso: a 60 FPS es fluido.
  framesPerSecond: 60,
);
