import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'enjambre_metamorfo_transparente',
  name: 'Enjambre Metamorfo Transparente',
  publication: CreatorPublication.draft,
  description:
      'Miles de partículas violeta y naranja que se transforman de esfera a toro, cubo, doble hélice y onda; respiran con los graves y estallan en los golpes fuertes sobre fondo transparente.',
  purposes: ['visualizer', 'party', 'club'],
  moods: ['futuristic', 'energetic', 'hypnotic'],
  concepts: ['particles', 'morphing', '3d shapes', 'swarm'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff8a2bff, 0xffff7a00, 0xffffffff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las partículas giran y se transforman sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
