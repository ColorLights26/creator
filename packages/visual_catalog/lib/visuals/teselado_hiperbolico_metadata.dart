import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'teselado_hiperbolico',
  name: 'Teselado Hiperbólico',
  publication: CreatorPublication.draft,
  description:
      'Mosaico infinito dentro de un círculo, como los de Escher: piezas rojas y negras con bordes dorados que se encogen hacia el borde y fluyen con la música.',
  purposes: ['visualizer', 'focus', 'relax'],
  moods: ['hypnotic', 'elegant', 'mathematical'],
  concepts: ['hyperbolic', 'poincare disk', 'escher', 'tessellation'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff000000, 0xffd8141e, 0xff160b08, 0xffffc046],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // El mosaico fluye sin parar: a 60 FPS es fluido.
  framesPerSecond: 30, // energía: ver energy/frame_rate_record.json
);
