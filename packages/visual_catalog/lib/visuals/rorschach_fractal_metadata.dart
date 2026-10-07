import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'rorschach_fractal',
  name: 'Rorschach Fractal',
  publication: CreatorPublication.draft,
  description:
      'Una mancha de Rorschach con borde fractal infinito que nunca se repite: el fractal viaja entre familias de formas, se acerca y se aleja, gira y salta a otra forma con cada golpe, con bandas de fuego que corren por el borde.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['mind-blowing', 'mathematical', 'hypnotic'],
  concepts: ['rorschach', 'julia set', 'fractal', 'infinite edge'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 4),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xfff0e8d8, 0xff0a0606, 0xffd0101e, 0xffffb21a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta cambia de forma sin parar: a 60 FPS es fluido.
  framesPerSecond: 30, // energía: 60 no cabe; ver energy/frame_rate_record.json
);
