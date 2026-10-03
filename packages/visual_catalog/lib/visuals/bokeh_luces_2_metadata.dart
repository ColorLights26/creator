import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'bokeh_luces_2',
  name: 'Bokeh 2',
  publication: CreatorPublication.draft,
  description:
      'Luces desenfocadas rojas, naranjas y amarillas intensas que laten con los graves y saltan hacia la cámara con cada golpe.',
  purposes: ['relax', 'visualizer', 'focus'],
  moods: ['dreamy', 'elegant', 'calm'],
  concepts: ['bokeh', 'lights', 'depth of field', 'glow'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff060000, 0xffff1a1a, 0xffffc400, 0xffff6a00],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las luces flotan sin parar: a 60 FPS la deriva es suave.
  framesPerSecond: 60,
);
