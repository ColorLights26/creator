import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'espiral_primos',
  name: 'Espiral de Primos',
  publication: CreatorPublication.draft,
  description:
      'Miles de números primos colocados en espiral: al alejarse aparecen brazos y rayos misteriosos de colores que respiran con la música, como en el famoso vídeo de 3Blue1Brown.',
  purposes: ['visualizer', 'focus', 'relax'],
  moods: ['mathematical', 'hypnotic', 'cosmic'],
  concepts: ['prime numbers', 'polar spiral', 'number theory', 'patterns'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 6),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff030106, 0xffff1f4b, 0xffff9a00, 0xffffe45a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // El zoom avanza de forma continua: a 60 FPS es fluido.
  framesPerSecond: 30, // energía: ver energy/frame_rate_record.json
);
