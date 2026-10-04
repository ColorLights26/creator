import 'package:scene_compositor/authoring.dart';

// One shape per modifier kind; pixels.json-style samples live in the tests.
const modifiers = [
  CreatorModifier.steps('lados', 'Cuadros', min: 3, max: 8, value: 4),
  CreatorModifier.slider('ancho', 'Ancho', min: .2, max: 1, value: .5),
  CreatorModifier.toggle('marco', 'Marco'),
  CreatorModifier.choice('tono', 'Tono', options: ['Azul', 'Amarillo']),
];

const nativeSource = r'''
class Visual final : public Scene {
 public:
  void reset(uint32_t) override {} void update(const Frame&) override {}
  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    c.scale(f.width/320, f.height/568);
    Paint p; p.color = f.colors[0]; c.rect({0, 0, 320, 568}, p);
    p.color = f.colors[1];
    for (int i = 0; i < m.lados; i++) c.rect({10.f + i * 36, 100, 30, 30}, p);
    p.color = f.colors[2]; c.rect({0, 200, 320 * m.ancho, 40}, p);
    if (m.marco) { p.color = f.colors[3]; c.rect({100, 300, 120, 40}, p); }
    p.color = m.tono == 0 ? Color{0, 0, 1, 1} : Color{1, 1, 0, 1};
    c.rect({100, 400, 120, 40}, p);
  }
};
''';
