import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'rorschach_calavera',
  name: 'Rorschach Calavera',
  publication: CreatorPublication.draft,
  description:
      'Una lámina de Rorschach en la que, a veces, el hueco de papel parece una calavera: nunca está dibujada, aparece y se disuelve con la tinta, y llora regueros de tinta con cada golpe.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['eerie', 'mysterious', 'dark'],
  concepts: ['rorschach', 'memento mori', 'negative space', 'pareidolia'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 4),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xffece4d4, 0xff100a0a, 0xff6a1410, 0xffd8c8a8],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta cambia de forma sin parar: a 60 FPS es fluido.
  framesPerSecond: 30, // energía: 60 no cabe; ver energy/frame_rate_record.json
);
