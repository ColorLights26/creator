import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'vitral_estalla',
  name: 'Vitral que Estalla',
  publication: CreatorPublication.draft,
  description:
      'Vitral de rubí, esmeralda y zafiro iluminado desde atrás que late con la música y en el drop estalla en fragmentos antes de recomponerse.',
  purposes: ['party', 'visualizer', 'epic'],
  moods: ['epic', 'dramatic', 'vivid'],
  concepts: ['stained glass', 'shatter', 'mosaic', 'light'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xff050306, 0xffd4102c, 0xff10b04e, 0xff1a4ee0],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // Fragmentos que vuelan: a 60 FPS el estallido es fluido.
  framesPerSecond: 30,
);
