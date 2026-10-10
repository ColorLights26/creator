import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'aura_2_transparente',
  name: 'Aura 2 Transparente',
  publication: CreatorPublication.draft,
  description:
      'Manchas de rojo encendido, naranja y azul eléctrico que giran, se funden y estallan en brillo con cada golpe sobre fondo transparente.',
  purposes: ['relax', 'focus', 'visualizer'],
  moods: ['calm', 'dreamy', 'elegant'],
  concepts: ['gradient', 'aura', 'blur', 'color'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xffff1744, 0xffff9100, 0xff2962ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Movimiento lento y continuo: a 60 FPS los degradados fluyen suaves.
  framesPerSecond: 30,
);
