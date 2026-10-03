import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'cimatica',
  name: 'Cimática',
  publication: CreatorPublication.draft,
  description:
      'El sonido hecho visible: arena luminosa que vibra sobre una placa y forma figuras geométricas que cambian con la música.',
  purposes: ['visualizer', 'party', 'relax'],
  moods: ['hypnotic', 'epic', 'scientific'],
  concepts: ['cymatics', 'chladni', 'sand', 'particles'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3.0),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff030712, 0xff1d4fa8, 0xffffcf73, 0xffffffff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La arena vibra sin parar: a 60 FPS los granos se mueven con fluidez.
  framesPerSecond: 60,
);
