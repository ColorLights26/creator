import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'v16_campo_magnetico_transparente',
  name: 'Campo Magnético Cuántico Transparente',
  publication: CreatorPublication.draft,
  description: 'Líneas de campo electromagnético transparentes con flujo de Lorentz, ferrofluido vibratorio y arcos Tesla.',
  purposes: ['energy', 'visualizer'],
  moods: ['tech', 'mystic'],
  concepts: ['magnetism', 'physics', 'energy'],
  credits: CreatorCredits(author: 'Visuales Inmersivas'),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0xff00f0ff, 0xffaa44ff, 0xffffffff, 0xff002040],
  controls: CreatorControls(intensity: 1.0, speed: 1.0, detail: 1.0, glow: 1.0),
);
