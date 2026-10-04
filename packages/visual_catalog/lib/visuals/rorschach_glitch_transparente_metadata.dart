import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'rorschach_glitch_transparente',
  name: 'Rorschach Glitch Transparente',
  publication: CreatorPublication.draft,
  description:
      'Una mancha de Rorschach corrupta: se rasga en franjas, se desdobla en fantasmas rojos y amarillos y se invierte de golpe con cada beat, como una señal que se rompe. Sin fondo: se ve lo que hay detrás.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['glitch', 'disturbing', 'intense'],
  concepts: ['rorschach', 'glitch', 'datamosh', 'strobe'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff060404, 0xffff1a2a, 0xffffd400],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta cambia de forma sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
