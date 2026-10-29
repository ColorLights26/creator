import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_choque_mareas',
  name: 'Reactiva Mejorada · Choque de Mareas (aprobada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con el golpe dos láminas de líquido luminoso, mandarina y lima, chocan a lo largo de una línea inclinada y la junta se levanta en pliegues desiguales que brillan amarillos; luego se retiran y se adelgazan desde los bordes lejanos. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['bold', 'fluid', 'energetic'],
  concepts: ['aparición momentánea', 'colliding currents', 'liquid fold', 'color fields'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff5a00, 0xff8cff10, 0xfffff8e0],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
