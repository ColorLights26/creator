import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'cordillera_sonido',
  name: 'Cordillera de Sonido',
  publication: CreatorPublication.draft,
  description:
      'La música dibuja una cordillera en 3D: cada fila es un instante de la canción y las cumbres avanzan hacia ti, al estilo Unknown Pleasures.',
  purposes: ['visualizer', 'focus', 'party'],
  moods: ['iconic', 'minimal', 'epic'],
  concepts: ['spectrum', 'terrain', 'waveform', 'joy division'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3.0),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff000000, 0xffffffff, 0xffa874ff, 0xff3a1d6e],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las filas avanzan sin parar: a 60 FPS el desplazamiento es suave.
  framesPerSecond: 30,
);
