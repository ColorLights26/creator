import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'muro_cinetico',
  name: 'Muro Cinético',
  publication: CreatorPublication.draft,
  description:
      'Pared de miles de plaquitas de plata que se mecen como con viento; olas de luz verde menta la recorren y cada golpe es una ráfaga que la hace destellar.',
  purposes: ['visualizer', 'relax', 'party'],
  moods: ['shimmering', 'elegant', 'hypnotic'],
  concepts: ['kinetic facade', 'wind', 'metal', 'reflections'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff111417, 0xff4dfcc4, 0xffd5dbe2, 0xffffffff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // El viento mueve la pared sin parar: a 60 FPS el brillo es fluido.
  framesPerSecond: 60,
);
