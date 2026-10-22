import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_cristal_electrico_transparente',
  name: 'Reactiva Mejorada · Cristal Eléctrico',
  publication: CreatorPublication.draft,
  description:
      'Versión reactiva mejorada: sin música no dibuja nada; con música se ve tanto como suena y cada golpe la enciende más. Una figura de Lichtenberg, el rayo fractal que se quema en la madera, crece ramificándose al rojo vivo; cada golpe manda una descarga blanca que recorre todas sus ramas sobre fondo transparente.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['electric', 'organic', 'intense'],
  concepts: ['aparición momentánea', 'reactiva mejorada', 'lichtenberg figure', 'fractal', 'lightning', 'growth'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.2),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffc81400, 0xffff7a00, 0xffffe680],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las ramas crecen paso a paso: a 60 FPS es fluido.
  framesPerSecond: 30,
);
