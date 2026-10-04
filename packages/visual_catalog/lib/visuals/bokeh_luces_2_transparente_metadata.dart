import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'bokeh_luces_2_transparente',
  name: 'Bokeh 2 Transparente',
  publication: CreatorPublication.draft,
  description:
      'Luces desenfocadas rojas, naranjas y amarillas intensas que laten con los graves y saltan hacia la cámara con cada golpe sobre fondo transparente.',
  purposes: ['relax', 'visualizer', 'focus'],
  moods: ['dreamy', 'elegant', 'calm'],
  concepts: ['bokeh', 'lights', 'depth of field', 'glow'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffff1a1a, 0xffffc400, 0xffff6a00],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las luces flotan sin parar: a 60 FPS la deriva es suave.
  framesPerSecond: 60,
);
