import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'campo_flujo',
  name: 'Campo de Flujo',
  publication: CreatorPublication.draft,
  description:
      'Corrientes de partículas luminosas con estelas de cometa que giran en grandes remolinos y estallan con cada golpe.',
  purposes: ['party', 'relax', 'visualizer'],
  moods: ['fluid', 'epic', 'hypnotic'],
  concepts: ['particles', 'flow field', 'trails', 'vortex'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff03030a, 0xff1fe2ff, 0xffff2fc2, 0xffffc93a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas en movimiento continuo: a 60 FPS las estelas son fluidas.
  framesPerSecond: 30,
);
