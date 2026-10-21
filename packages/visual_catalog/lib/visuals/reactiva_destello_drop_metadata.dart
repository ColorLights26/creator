import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'reactiva_destello_drop',
  name: 'Reactiva · Destello de Drop',
  publication: CreatorPublication.draft,
  description:
      'Sólo en el golpe grande (el primero tras una pausa o uno mucho más fuerte que los anteriores) se abre desde el centro una luz suave que se apaga enseguida. Aparece muy de vez en cuando. Sin música no dibuja nada.',
  purposes: ['visualizer', 'overlay', 'momentary'],
  moods: ['subtle', 'dramatic', 'bright'],
  concepts: ['aparición momentánea', 'drop', 'light burst', 'impact'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 1.12),
  role: CreatorRole.overlay,
  // Sólo con música: sin ella la capa queda vacía.
  reactivity: CreatorReactivity.music,
  colors: [0x00000000, 0xff000000, 0xffffd6a0, 0xfffff7ea],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Sin música no dibuja nada; sólo aparece un instante con su momento. Dibuja como mucho unos rectángulos con degradado.
  framesPerSecond: 30,
);
