import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'v02_red_neuronal_transparente',
  name: 'Red Neuronal Cuántica Transparente',
  publication: CreatorPublication.draft,
  description: 'Plexo neuronal transparente con potenciales de acción, sinapsis bioluminiscentes e impulsos reactivos.',
  purposes: ['hud', 'visualizer'],
  moods: ['tech', 'cosmic'],
  concepts: ['neural', 'network', 'ai'],
  credits: CreatorCredits(author: 'Visuales Inmersivas v02 (Overlay)'),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0xff00f0ff, 0xff7000ff, 0xffffffff, 0xff003366],
  controls: CreatorControls(intensity: 1.0, speed: 1.0, detail: 1.0, glow: 1.0),
);
