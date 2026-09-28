// Aurora Boreal — port de la galería immersive a escena nativa.
// Cintas de luz sobre cielo estrellado, con reacción musical opcional.
const nativeSource = r'''
class Visual final : public Scene {
  struct Star { float x, y, tw; };
  std::vector<Star> stars;
  float breath = 0, flash = 0;
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
  void reset(uint32_t seed) override {
    Random rng(seed); stars.clear(); stars.reserve(110); breath = 0; flash = 0;
    for (int i = 0; i < 110; i++)
      stars.push_back({rng.unit(), rng.unit() * 0.62f, rng.unit() * 6.2831853f});
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
    float glow = (0.8f + 0.35f * breath + 0.5f * flash) * f.intensity;
    Paint sky = Paint::linear({0, 0}, {0, h},
      {Color::argb(0xff01030f), Color::argb(0xff04122b),
       Color::argb(0xff062033), Color::argb(0xff010409)}, {0, 0.45f, 0.8f, 1.0f});
    c.rect({0, 0, w, h}, sky);
    std::vector<Vec2> batch; batch.reserve(stars.size());
    for (const auto& s : stars) batch.push_back({s.x * w, s.y * h});
    Paint sp; sp.blend = Blend::plus;
    sp.color = {1, 1, 1, (0.35f + 0.25f * std::abs(std::sin(t * 0.9f))) * glow};
    c.points(batch, 1.6f, sp);
    const float cy[4] = {0.30f, 0.36f, 0.44f, 0.50f};
    const float am[4] = {0.05f, 0.06f, 0.045f, 0.035f};
    const float th[4] = {0.20f, 0.16f, 0.13f, 0.09f};
    const float sp2[4] = {0.18f, -0.25f, 0.33f, -0.40f};
    const float fr[4] = {1.7f, 2.3f, 3.1f, 4.2f};
    const uint32_t col[4] = {0xff38ffc4, 0xff4be0ff, 0xff9d6bff, 0xffff5fd2};
    for (int b = 0; b < 4; b++) {
      float amp = am[b] * (1.0f + 0.4f * breath);
      Path ribbon;
      for (int i = 0; i <= 26; i++) {
        float x = float(i) / 26.0f * w;
        float n = vnoise(float(i) * 0.22f + t * sp2[b], float(b) * 5.5f + t * 0.15f);
        float y = h * cy[b] + std::sin(float(i) * fr[b] * 0.14f + t * sp2[b] * 3.0f) * h * amp
          + (n - 0.5f) * h * 0.07f;
        if (i == 0) ribbon.moveTo(x, y); else ribbon.lineTo(x, y);
      }
      for (int i = 26; i >= 0; i--) {
        float x = float(i) / 26.0f * w;
        float n = vnoise(float(i) * 0.22f + t * sp2[b], float(b) * 5.5f + t * 0.15f);
        float y = h * cy[b] + std::sin(float(i) * fr[b] * 0.14f + t * sp2[b] * 3.0f) * h * amp
          + (n - 0.5f) * h * 0.07f + h * th[b] * (0.6f + n * 0.8f);
        ribbon.lineTo(x, y);
      }
      ribbon.close();
      Color base = Color::argb(col[b]);
      Paint band = Paint::linear({0, h * (cy[b] - amp - th[b])}, {0, h * (cy[b] + amp + 0.02f)},
        {{base.r, base.g, base.b, 0}, {base.r, base.g, base.b, 0.40f * glow},
         {base.r, base.g, base.b, 0}}, {0, 0.45f, 1.0f});
      band.blend = Blend::plus;
      c.path(ribbon, band);
    }
    Path ridge; ridge.moveTo(0, h);
    for (int i = 0; i < 42; i++)
      ridge.lineTo(float(i) / 41.0f * w,
        h * (0.8f + vnoise(float(i) * 0.35f, 3.0f) * 0.12f) - float(std::abs(i - 20)) * 0.8f);
    ridge.lineTo(w, h); ridge.close();
    Paint dk; dk.color = Color::argb(0xff01050c);
    c.path(ridge, dk);
  }
};
''';
