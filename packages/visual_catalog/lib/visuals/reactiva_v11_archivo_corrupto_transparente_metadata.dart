import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_v11_archivo_corrupto_transparente',
  name: 'Reactiva · Archivo Corrupto',
  publication: CreatorPublication.draft,
  description: 'Versión reactiva: sin música no dibuja nada y sólo aparece un instante con el golpe grande (o el momento que elijas en Ajustes) y desaparece. Filtro glitch transparente con aberración cromática RGB aditiva, datamosh y saltos de escaneo en los bombos.',
  purposes: ['hud', 'fx'],
  moods: ['glitch', 'cyberpunk'],
  concepts: ['aparición momentánea', 'glitch', 'crt', 'datamosh'],
  credits: CreatorCredits(author: 'Visuales Inmersivas'),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.2),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.music,
  colors: [0xffff0055, 0xff00ffcc, 0xffffff00, 0xff330033],
  controls: CreatorControls(intensity: 1.0, speed: 1.0, detail: 1.0, glow: 1.0),
);
