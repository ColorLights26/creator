import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_bengala_humo',
  name: 'Reactiva · Bengala de Humo (aprobada por la crítica)',
  publication: CreatorPublication.draft,
  description:
      'Con el golpe revienta desde un lado una bengala de humo verde esmeralda encendido: una columna espesa que sale a borbotones y se hincha en volutas que ruedan, brillante cerca de la boca; al cortarse se despega y se aclara hasta desaparecer. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['bold', 'warm', 'dramatic'],
  concepts: ['aparición momentánea', 'smoke bomb', 'colored smoke', 'billows'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff00a030, 0xff20ff50, 0xffa0ff70],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
