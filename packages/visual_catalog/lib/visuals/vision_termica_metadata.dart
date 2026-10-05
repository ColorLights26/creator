import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'vision_termica',
  name: 'Visión Térmica',
  publication: CreatorPublication.draft,
  description:
      'La fiesta vista con una cámara de calor: manchas, bailarines o aire caliente en negro, morado, rojo, naranja y amarillo, con el visor de la cámara; cada golpe es un fogonazo de calor.',
  purposes: ['visualizer', 'party'],
  moods: ['intense', 'futuristic', 'warm'],
  concepts: ['thermal camera', 'infrared', 'heat map', 'flir'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff05020f, 0xff6a0d8c, 0xffff3a12, 0xffffd23a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // El calor se mueve despacio: 30 FPS bastan.
  framesPerSecond: 30,
);
