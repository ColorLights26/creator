import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'espectrograma',
  name: 'Espectrograma',
  publication: CreatorPublication.draft,
  description:
      'La música vista como un mapa de calor que cae como una cascada: cada fila es un instante y cada columna una frecuencia; de vez en cuando aparece una figura escondida en el sonido, como hizo Aphex Twin.',
  purposes: ['visualizer', 'focus', 'party'],
  moods: ['scientific', 'hypnotic', 'warm'],
  concepts: ['spectrogram', 'waterfall', 'frequency', 'hidden image'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 6),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff030002, 0xffc8101e, 0xffff8a00, 0xffffe86a],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Las filas avanzan de forma continua: a 60 FPS es fluido.
  framesPerSecond: 60,
);
