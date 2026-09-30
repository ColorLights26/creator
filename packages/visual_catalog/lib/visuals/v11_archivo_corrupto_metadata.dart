import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'v11_archivo_corrupto',
  name: 'Archivo Corrupto',
  publication: CreatorPublication.draft,
  description: 'Fallo digital de archivo y datamosh estructurado, canales RGB cromáticos aditivos, barrido CRT y franja VHS rodante reactiva al ritmo.',
  purposes: ['cyberpunk', 'visualizer', 'glitch'],
  moods: ['intense', 'hypnotic', 'digital'],
  concepts: ['glitch', 'datamosh', 'vhs', 'cyberpunk', 'artifact'],
  credits: CreatorCredits(author: 'Visuales Inmersivas', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.0),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff0a0a12, 0xffff2e88, 0xff00f0ff, 0xffffe14d],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
