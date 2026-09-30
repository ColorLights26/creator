// Horizonte Synthwave — port de la galería immersive a escena nativa.
// Sol retro con rejilla infinita y montañas de neón estilo años 80.
const nativeSource = r'''
class Visual final : public Scene {
  std::vector<float> ridge;
  float pulse = 0;
  static float vhash(int x, int y) {
    uint32_t h = uint32_t(x) * 374761393u + uint32_t(y) * 668265263u;
    h = (h ^ (h >> 13)) * 1274126177u; h ^= h >> 16;
    return float(h & 0xffffu) / 65535.0f;
  }
  static float vnoise(float x, float y) {
    int xi = int(std::floor(x)), yi = int(std::floor(y));
    float xf = x - float(xi), yf = y - float(yi);
    float u = xf * xf * (3.0f - 2.0f * xf), v = yf * yf * (3.0f - 2.0f * yf);
    float a = vhash(xi, yi), b = vhash(xi + 1, yi);
    float c = vhash(xi, yi + 1), d = vhash(xi + 1, yi + 1);
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
  }
 public:
  Visual() {
    reset(0);
  }
  void reset(uint32_t seed) override {
    (void)seed;
    pulse = 0;
    ridge.resize(30);
    for (int i = 0; i < 30; i++)
      ridge[i] = (vnoise(float(i) * 0.4f, 1.0f) * 0.5f + vnoise(float(i) * 0.9f, 7.0f) * 0.5f);
  }
  void update(const Frame& f) override {
    if (ridge.size() != 30) {
      reset(0);
    }
    for (const auto& band : f.music.events)
      for (const auto& e : band) pulse += e.strength;
    pulse *= float(std::exp(-f.delta * 4.0));
  }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float t = float(f.time) * f.speed;
    float hz = h * 0.56f;
    float glowBoost = (0.7f + 0.6f * f.music.bass + 0.8f * pulse) * f.intensity;
    if (glowBoost > 1.0f) glowBoost = 1.0f; if (glowBoost < 0.0f) glowBoost = 0.0f;
    Paint sky = Paint::linear({0, 0}, {0, hz},
      {Color::argb(0xff160034), Color::argb(0xff4a0a6b), Color::argb(0xffff4d78)}, {0, 0.55f, 1.0f});
    c.rect({0, 0, w, hz}, sky);
    float sr = std::min(w, h) * 0.22f;
    float sunCx = w * 0.5f, sunCy = hz - sr * 0.15f;
    c.save();
    Path sunClip; sunClip.circle({sunCx, sunCy}, sr);
    c.clip(sunClip);
    Paint sun = Paint::linear({0, hz - sr * 1.3f}, {0, hz + 4.0f},
      {Color::argb(0xfffff36b), Color::argb(0xffff8a3d), Color::argb(0xffff2e9a)}, {0, 0.45f, 1.0f});
    c.rect({sunCx - sr, hz - sr * 1.3f, sr * 2.0f, sr * 2.0f}, sun);
    Paint bar; bar.color = Color::argb(0xff160034);
    float lane = sr * 0.14f;
    float off = std::fmod(t * 14.0f, lane);
    for (int i = 0; i < 9; i++) {
      float y = hz - sr * 0.9f + float(i) * lane + off;
      c.rect({sunCx - sr, y, sr * 2.0f, float(i) * 0.55f + 1.5f}, bar);
    }
    c.restore();
    Path mtn; mtn.moveTo(0, hz);
    if (ridge.size() == 30) {
      for (int i = 0; i < 30; i++)
        mtn.lineTo(float(i) / 29.0f * w, hz - ridge[i] * h * 0.16f);
    }
    mtn.lineTo(w, hz); mtn.close();
    Paint mfill; mfill.color = Color::argb(0xff0d0020);
    c.path(mtn, mfill);
    Paint mstroke; mstroke.color = {1, 0.435f, 0.847f, std::min(1.0f, 0.9f * f.intensity)};
    mstroke.strokeWidth = 1.0f;
    c.path(mtn, mstroke);
    Paint floor = Paint::linear({0, hz}, {0, h},
      {Color::argb(0xff12002b), Color::argb(0xff2a004d)});
    c.rect({0, hz, w, h - hz}, floor);
    Path grid;
    for (int i = -9; i <= 9; i++) {
      grid.moveTo(w * 0.5f, hz);
      grid.lineTo(w * 0.5f + float(i) * w * 0.34f, h);
    }
    float speed = std::fmod(t * 0.55f, 1.0f);
    for (int i = 0; i < 16; i++) {
      float k = (float(i) + speed) / 16.0f;
      float y = hz + (h - hz) * k * k * 1.02f;
      if (y > h) continue;
      grid.moveTo(0, y); grid.lineTo(w, y);
    }
    Paint gp; gp.color = {0, 1, 0.965f, std::min(1.0f, 0.75f * f.intensity)};
    gp.strokeWidth = 1.1f;
    c.path(grid, gp);
    Paint hg = Paint::linear({0, hz - 26.0f}, {0, hz + 26.0f},
      {{1, 0.18f, 0.604f, 0}, {1, 0.47f, 0.784f, 0.35f * glowBoost}, {0, 1, 0.965f, 0}}, {0, 0.5f, 1.0f});
    hg.blend = Blend::plus;
    c.rect({0, hz - 26.0f, w, 52.0f}, hg);
  }
};
''';
