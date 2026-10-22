import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_destellos_dorados_premium',
  name: 'Reactiva Mejorada · Destellos Dorados Premium',
  publication: CreatorPublication.draft,
  description:
      'Versión reactiva mejorada: sin música no dibuja nada; con música se ve tanto como suena y cada golpe la enciende más. Estrellas doradas que aparecen, titilan con rayos finos de luz y se apagan sobre un polvo de oro que flota y unas luces doradas desenfocadas. Sin fondo, encima de cualquier visual.',
  purposes: ['visualizer', 'party', 'overlay'],
  moods: ['magical', 'glamorous', 'festive'],
  concepts: ['aparición momentánea', 'reactiva mejorada', 'sparkles', 'stars', 'gold', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.2),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffa8700a, 0xffffc23d, 0xfffff4d6],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Partículas simuladas con física: fluidas a 30 FPS en el móvil.
  framesPerSecond: 30,
);
