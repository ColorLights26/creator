import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'circulo_trap',
  name: 'Círculo Trap',
  publication: CreatorPublication.draft,
  description:
      'El visualizador circular más imitado de YouTube: varias ondas circulares de colores superpuestas que bailan con el espectro, temblor de pantalla con los graves y partículas que salen despedidas.',
  purposes: ['visualizer', 'party', 'club'],
  moods: ['energetic', 'bold', 'club'],
  concepts: ['audio spectrum', 'circular visualizer', 'trap nation style', 'particles'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff0a0306, 0xffff1a3c, 0xffff8a00, 0xffffe14a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // El círculo late con cada fotograma de la música: a 60 FPS es fluido.
  framesPerSecond: 30, // energía: 60 no cabe; ver energy/frame_rate_record.json
);
