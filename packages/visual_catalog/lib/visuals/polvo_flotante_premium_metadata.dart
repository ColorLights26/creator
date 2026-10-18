import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'polvo_flotante_premium',
  name: 'Polvo Flotante Premium',
  publication: CreatorPublication.draft,
  description:
      'Polvo de luz en el espacio: miles de motas diminutas que flotan en corrientes de aire, titilan y se apagan, con alguna mota cercana grande y desenfocada. Sin fondo, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['calm', 'dreamy', 'elegant'],
  concepts: ['dust', 'floating particles', 'depth of field', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0x00000000, 0xff7d8aa6, 0xffd6dde8, 0xffffffff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas simuladas con física: fluidas a 30 FPS en el móvil.
  framesPerSecond: 30,
);
