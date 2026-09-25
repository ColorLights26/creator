import 'package:scene_compositor/authoring.dart';

// Datos del visual. El código se encuentra en el archivo del mismo nombre
// sin el sufijo _metadata. ID único; aparece en Studio. Color Lights exige revisión.
const metadata = CreatorVisualMetadata(
  id: 'my_visual',
  name: 'Mi visual',
  publication: CreatorPublication.draft,
  description: 'Una galaxia de estrellas que se mueve y responde a la música.',
  purposes: ['relax', 'visualizer'],
  moods: ['calm', 'dreamy'],
  concepts: ['galaxy', 'stars', 'space'],
  credits: CreatorCredits(author: '', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5),
  // Recursos opcionales. Guarda cada imagen en packages/visual_catalog/assets/images/.
  // images: {'planet': 'assets/images/planet.png'},
  role: CreatorRole.background,
  // optional: interruptor; music: reacción activada; none: sin reacción.
  // Apagar la reacción pone las señales en cero, sin detener el tiempo del dibujo.
  reactivity: CreatorReactivity.optional,
  colors: [0xff030918, 0xff20d7ba, 0xff6562eb, 0xffffb9de],
  controls: CreatorControls(intensity: 1, speed: .6, detail: 1, glow: .8),
);
