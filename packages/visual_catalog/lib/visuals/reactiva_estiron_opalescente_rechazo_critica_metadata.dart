import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_estiron_opalescente_rechazo_critica',
  name: 'Reactiva · Estirón Opalescente (rechazada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Con el golpe una masa de líquido lechoso se estira en dos lenguas desiguales por un eje curvo; lo grueso brilla bermellón y lo fino ultramar, y se apaga desde las puntas. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['bold', 'fluid', 'strange'],
  concepts: ['aparición momentánea', 'extensional flow', 'tyndall scattering', 'colloid'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff2a08, 0xff2a1cff, 0xfffff2ee],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
