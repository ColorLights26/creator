// Galaxia Espiral — port de la galería immersive a escena nativa.
// 1500 estrellas en 3 brazos orbitando un núcleo incandescente.
const nativeSource = r'''
class Visual final : public Scene {
  struct Star { float radius, angle, speed; int group; };
  std::vector<Star> stars;
  float breath = 0, flash = 0;
 public:
  void reset(uint32_t seed) override {
    Random rng(seed); stars.clear(); stars.reserve(1500); breath = 0; flash = 0;
    for (int i = 0; i < 1500; i++) {
      float r = std::pow(rng.unit(), 0.65f);
      int arm = i % 3;
      float a = float(arm) / 3.0f * float(pi) * 2.0f + r * 3.4f
        + (rng.unit() - 0.5f) * (0.5f + (1.0f - r) * 1.6f);
      stars.push_back({r, a, 0.55f / (0.25f + r * 1.5f), r < 0.3f ? 0 : 1 + int(rng.unit() * 3.0f)});
    }
  }
  void update(const Frame& f) override {
    breath += (f.music.energy - breath) * float(1.0 - std::exp(-f.delta * 3.0));
    for (const auto& band : f.music.events)
      for (const auto& e : band) flash += e.strength;
    flash *= float(std::exp(-f.delta * 4.0));
  }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float t = float(f.time) * f.speed;
    float cx = w * 0.5f, cy = h * 0.5f;
    float rMax = std::min(w, h) * 0.46f * (1.0f + breath * 0.05f);
    Paint bg; bg.color = Color::argb(0xff03020a);
    c.rect({0, 0, w, h}, bg);
    Paint core = Paint::radial({cx, cy}, rMax,
      {Color{1, 0.925f, 0.784f, 0.75f}, Color{1, 0.55f, 0.784f, 0.22f},
       Color{0.35f, 0.235f, 0.784f, 0.12f}, Color{0, 0, 0, 0}}, {0, 0.18f, 0.55f, 1.0f});
    core.blend = Blend::plus;
    c.rect({0, 0, w, h}, core);
    for (int group = 0; group < 4; group++) {
      std::vector<Vec2> batch; batch.reserve(400);
      for (const auto& s : stars) {
        if (s.group != group) continue;
        float a = s.angle + t * s.speed * 0.35f;
        float rr = s.radius * rMax * (1.0f + std::sin(t * 0.6f + s.angle * 7.0f) * 0.012f);
        batch.push_back({cx + std::cos(a) * rr, cy + std::sin(a) * rr * 0.42f + std::sin(a * 2.0f) * 4.0f});
      }
      Paint p; p.blend = Blend::plus;
      if (group == 0) p.color = {1, 0.914f, 0.722f, (0.75f + 0.25f * flash) * f.intensity};
      else if (group == 1) p.color = {1, 0.604f, 0.835f, (0.6f + 0.3f * flash) * f.intensity};
      else if (group == 2) p.color = {0.478f, 0.843f, 1, (0.6f + 0.3f * flash) * f.intensity};
      else p.color = {0.780f, 0.608f, 1, (0.65f + 0.3f * flash) * f.intensity};
      c.points(batch, group == 0 ? 2.0f : 1.4f, p);
    }
  }
};
''';
