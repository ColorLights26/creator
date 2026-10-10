import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'selva_bioluminiscente',
  name: 'Selva Bioluminiscente',
  publication: CreatorPublication.draft,
  description:
      'Un bosque de noche que brilla con luz propia: ramas retorcidas con hojas verde menta, setas ámbar, helechos encendidos, niebla con rayos de luna, esporas y luciérnagas; cada golpe lanza un pulso de luz que sube desde las raíces hasta las hojas.',
  purposes: ['relax', 'visualizer'],
  moods: ['calm', 'magical'],
  concepts: ['forest', 'bioluminescence', 'glow', 'night'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff010805, 0xff3dffa0, 0xffff7a00, 0xff00c853],
  controls: CreatorControls(intensity: 1, speed: .6, detail: 1, glow: 1),
);
