import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'rorschach_caleidoscopio_transparente',
  name: 'Rorschach Caleidoscopio Transparente',
  publication: CreatorPublication.draft,
  description:
      'Una mancha de Rorschach con simetría de caleidoscopio: tintas roja, naranja y amarilla sobre negro que giran, se pliegan y estallan en anillos con la música. Sin fondo: se ve lo que hay detrás.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['psychedelic', 'hypnotic', 'intense'],
  concepts: ['rorschach', 'kaleidoscope', 'radial symmetry', 'ink'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffd8001e, 0xffff7a00, 0xffffe03a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta cambia de forma sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
