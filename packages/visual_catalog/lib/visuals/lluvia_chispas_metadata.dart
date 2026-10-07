import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'lluvia_chispas',
  name: 'Lluvia de Chispas',
  publication: CreatorPublication.draft,
  description:
      'Chorros de chispas de metal al rojo vivo como los de una radial en cámara lenta: estelas blancas, amarillas y naranjas que vuelan, rebotan en el suelo y estallan con cada golpe.',
  purposes: ['visualizer', 'party', 'club'],
  moods: ['intense', 'industrial', 'energetic'],
  concepts: ['sparks', 'grinder', 'particles', 'slow motion'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff050302, 0xffd82a00, 0xffff8a00, 0xffffe066],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las chispas se calculan a 120 pasos por segundo.
  framesPerSecond: 30, // energía: ver energy/frame_rate_record.json
);
