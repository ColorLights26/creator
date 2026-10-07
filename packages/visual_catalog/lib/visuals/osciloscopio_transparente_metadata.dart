import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'osciloscopio_transparente',
  name: 'Osciloscopio Transparente',
  publication: CreatorPublication.draft,
  description:
      'Un haz de luz verde eléctrico dibuja figuras que se transforman — espirales, flores y nudos en 3D — y que la música deforma y hace saltar sobre fondo transparente.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['retro', 'technical', 'hypnotic'],
  concepts: ['oscilloscope', 'lissajous', 'vector', 'phosphor'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff39ff14, 0xffb6ff9e, 0xffffffff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // El haz se mueve sin parar: a 60 FPS las figuras son fluidas.
  framesPerSecond: 30, // energía: ver energy/frame_rate_record.json
);
