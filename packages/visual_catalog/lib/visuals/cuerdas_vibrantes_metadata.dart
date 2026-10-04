import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'cuerdas_vibrantes',
  name: 'Cuerdas Vibrantes',
  publication: CreatorPublication.draft,
  description:
      'El famoso efecto de las cuerdas de guitarra grabadas desde dentro: cuerdas doradas y plateadas que ondulan en serpientes de luz, cada una con su banda de la música, bajo una luz roja.',
  purposes: ['visualizer', 'relax', 'party'],
  moods: ['warm', 'musical', 'hypnotic'],
  concepts: ['guitar strings', 'rolling shutter', 'vibration', 'waves'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff070302, 0xffff2a12, 0xffffc04a, 0xfff4f4ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las ondas corren por las cuerdas sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
