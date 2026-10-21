import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_cristal_electrico_transparente',
  name: 'Reactiva · Cristal Eléctrico',
  publication: CreatorPublication.draft,
  description:
      'Versión reactiva: sin música no dibuja nada y sólo aparece un instante con el golpe grande (o el momento que elijas en Ajustes) y desaparece. Una figura de Lichtenberg, el rayo fractal que se quema en la madera, crece ramificándose al rojo vivo; cada golpe manda una descarga blanca que recorre todas sus ramas sobre fondo transparente.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['electric', 'organic', 'intense'],
  concepts: ['aparición momentánea', 'lichtenberg figure', 'fractal', 'lightning', 'growth'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.2),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffc81400, 0xffff7a00, 0xffffe680],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las ramas crecen paso a paso: a 60 FPS es fluido.
  framesPerSecond: 30,
);
