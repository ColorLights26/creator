import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_show_laser_transparente',
  name: 'Reactiva · Show Láser',
  publication: CreatorPublication.draft,
  description:
      'Versión reactiva: sin música no dibuja nada y sólo aparece un instante con el golpe grande (o el momento que elijas en Ajustes) y desaparece. Espectáculo de láseres de festival: abanicos de rayos de colores que barren el humo, se abren y destellan con cada golpe sobre fondo transparente.',
  purposes: ['party', 'visualizer'],
  moods: ['epic', 'energetic', 'club'],
  concepts: ['aparición momentánea', 'lasers', 'beams', 'festival', 'light show'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.2),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff1e5a, 0xff2bff6a, 0xff1ec8ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
);
