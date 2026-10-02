import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'v11_archivo_corrupto_transparente',
  name: 'Archivo Corrupto Transparente',
  publication: CreatorPublication.draft,
  description: 'Filtro glitch transparente con aberración cromática RGB aditiva, datamosh y saltos de escaneo en los bombos.',
  purposes: ['hud', 'fx'],
  moods: ['glitch', 'cyberpunk'],
  concepts: ['glitch', 'crt', 'datamosh'],
  credits: CreatorCredits(author: 'Visuales Inmersivas'),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0xffff0055, 0xff00ffcc, 0xffffff00, 0xff330033],
  controls: CreatorControls(intensity: 1.0, speed: 1.0, detail: 1.0, glow: 1.0),
);
