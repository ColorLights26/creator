import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'placa_circuitos_transparente',
  name: 'Placa de Circuitos Transparente',
  publication: CreatorPublication.draft,
  description:
      'Una placa de circuitos ámbar vista de cerca: paquetes de datos corren por las pistas y con cada golpe el chip central dispara una onda de energía que recorre toda la placa sobre fondo transparente.',
  purposes: ['visualizer', 'focus', 'party'],
  moods: ['tech', 'futuristic', 'warm'],
  concepts: ['circuit board', 'pcb', 'data', 'energy pulse'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffff9a1f, 0xffff3b0f, 0xfffff1c4],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Los paquetes corren sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
