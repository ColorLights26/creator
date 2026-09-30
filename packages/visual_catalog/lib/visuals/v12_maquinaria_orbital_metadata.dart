import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'v12_maquinaria_orbital',
  name: 'Maquinaria Orbital',
  publication: CreatorPublication.draft,
  description: 'Planetario astrológico de relojería en latón y piedra, cuatro esferas orbitantes en planos inclinados con sombras arrojadas y sol central iluminado.',
  purposes: ['mechanical', 'relax', 'visualizer'],
  moods: ['mysterious', 'hypnotic', 'elegant'],
  concepts: ['orrery', 'astrolabe', 'clockwork', 'planets', 'brass', 'astronomy'],
  credits: CreatorCredits(author: 'Visuales Inmersivas', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3.0),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff14100c, 0xffd98b4a, 0xffb8a06a, 0xff6f9ec4],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
