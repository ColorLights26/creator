import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_destello_drop',
  name: 'Reactiva · Destello de Drop',
  publication: CreatorPublication.draft,
  description:
      'Sólo en el golpe grande se abre una luz desde el centro o desde abajo: un núcleo quemado con caída de luz real que crece en tres cuadros y se apaga encogiéndose hasta una brasa roja, y un frente de luz roja suave que se aleja. Aparece muy de vez en cuando. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['euphoric', 'warm', 'dramatic'],
  concepts: ['aparición momentánea', 'drop', 'bloom', 'flash'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.0),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xffff2a10, 0xffffa020, 0xfffff6ea],
  images: {},
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece con su momento musical.
  framesPerSecond: 30,
);
