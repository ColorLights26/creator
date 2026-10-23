import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_mejorada_vineta_late',
  name: 'Reactiva Mejorada · Viñeta que Late',
  publication: CreatorPublication.draft,
  description:
      'Versión mejorada: aparece con el ritmo de la música (cada golpe o cada tiempo) y crece con el volumen; sin música no dibuja nada. Con el golpe, los bordes de la escena se oscurecen un instante como al mirar por un objetivo: viñeta sin color de caída larga y suave (óvalo, laterales o arriba y abajo) con el centro intacto. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['cinematic', 'dark', 'rhythmic'],
  concepts: ['aparición momentánea', 'vignette', 'lens', 'pulse'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff000000, 0xffffc27a, 0xfffff7ea],
  images: {'noise': 'assets/images/reactiva_quemado.png'},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
