import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_destellos_anamorficos',
  name: 'Reactiva Mejorada · Destellos Anamórficos',
  publication: CreatorPublication.draft,
  description:
      'Versión reactiva mejorada: sin música no dibuja nada; con música se ve tanto como suena y cada golpe la enciende más. Luces con las rayas horizontales de las lentes de cine, estrellas de difracción o arcos, sin fondo para ponerlas encima de otro visual; cada golpe de la música hace estallar algunas.',
  purposes: ['visualizer', 'party'],
  moods: ['cinematic', 'futuristic', 'glamorous'],
  concepts: ['aparición momentánea', 'reactiva mejorada', 'anamorphic lens flare', 'sci-fi', 'light streaks', 'overlay'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.2),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff2a6bff, 0xffff7010, 0xffeaf2ff],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las luces cruzan rápido: a 60 FPS es fluido.
  framesPerSecond: 30,
);
