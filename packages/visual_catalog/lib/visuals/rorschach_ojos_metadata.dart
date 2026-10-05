import 'package:scene_compositor/authoring.dart';

const metadata = CreatorVisualMetadata(
  id: 'rorschach_ojos',
  name: 'Rorschach Ojos',
  publication: CreatorPublication.draft,
  description:
      'Una mancha de Rorschach llena de ojos que se abren y se cierran por su cuenta, se mueven nerviosos y, con cada golpe, se multiplican y te miran todos a la vez con las pupilas dilatadas.',
  purposes: ['visualizer', 'party', 'focus'],
  moods: ['disturbing', 'eerie', 'surreal'],
  concepts: ['rorschach', 'eyes', 'pareidolia', 'watching'],
  credits: CreatorCredits(author: 'Chic Apps', license: '', source: ''),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 4),
  role: CreatorRole.background,
  reactivity: CreatorReactivity.optional,
  colors: [0xffe7dcc8, 0xff0b0706, 0xffc4121e, 0xfffff4e6],
  controls: CreatorControls(intensity: 1, speed: 1, detail: 1, glow: 1),
  // La tinta cambia de forma sin parar: a 60 FPS es fluido.
  framesPerSecond: 60,
);
