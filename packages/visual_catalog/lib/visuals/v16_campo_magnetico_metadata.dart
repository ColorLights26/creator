import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'v16_campo_magnetico',
  name: 'Campo Magnético Cuántico',
  publication: CreatorPublication.draft,
  description: 'Acelerador magnético de alta energía: dipolo con tubos de flujo aurorales, plasma de Lorentz en espirales ciclotrón, arcos eléctricos Tesla y ferrofluido reactivo.',
  purposes: ['scientific', 'visualizer', 'energy'],
  moods: ['epic', 'intense', 'hypnotic', 'futuristic'],
  concepts: ['magnetic field', 'electromagnet', 'plasma', 'tesla', 'lorentz', 'ferrofluid'],
  credits: CreatorCredits(author: 'Visuales Inmersivas', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.0),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff080b12, 0xff00f0ff, 0xff9d4edd, 0xffffb703],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
