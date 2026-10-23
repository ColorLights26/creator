import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_camara_niebla_rechazo_critica',
  name: 'Reactiva Mejorada · Cámara de Niebla (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con el golpe aparecen trazas de partículas como en una cámara de niebla: una estrella de trazas gruesas, espirales finas, rayas que cruzan la pantalla y rizos cortos, hechas de gotitas de luz blanca con halo azul frío que se dispersan y se pierden. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['strange', 'scientific', 'cool'],
  concepts: ['aparición momentánea', 'cloud chamber', 'particle tracks', 'radiation'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff2a4aff, 0xff7aa8ff, 0xfff4f8ff],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
