// Malla de Ondas — port de la galería immersive a escena nativa.
// Miles de puntos azules ondulando como agua vista desde arriba.
const nativeSource = r'''
class Visual final : public Scene {
  std::vector<Vec2> buckets[6];
  float step = 12.0f, cols = 0, rows = 0, lastW = 0, lastH = 0, lastDetail = -1.0f;
  void build(float w, float h, float detail) {
    step = std::max(9.0f, std::min(w, h) / (18.0f + 16.0f * detail));
    cols = std::ceil(w / step) + 1.0f;
    rows = std::ceil(h / step) + 1.0f;
  }
 public:
  void reset(uint32_t seed) override {
    (void)seed;
    for (int i = 0; i < 6; i++) buckets[i].clear();
    lastW = 0; lastH = 0; lastDetail = -1.0f;
  }
  void update(const Frame& f) override {
    float w = f.width, h = f.height;
    float t = float(f.time) * f.speed;
    if (w != lastW || h != lastH || f.detail != lastDetail) {
      build(w, h, f.detail);
      lastW = w; lastH = h; lastDetail = f.detail;
    }
    float amp = 1.0f + f.music.bass * 0.6f;
    float s1x = w * (0.5f + std::sin(t * 0.35f) * 0.32f);
    float s1y = h * (0.35f + std::sin(t * 0.27f + 1.0f) * 0.2f);
    float s2x = w * (0.5f + std::sin(t * 0.31f + 2.4f) * 0.34f);
    float s2y = h * (0.68f + std::sin(t * 0.23f + 3.0f) * 0.2f);
    for (int i = 0; i < 6; i++) buckets[i].clear();
    for (int j = 0; j < int(rows); j++) {
      float y = float(j) * step;
      for (int i = 0; i < int(cols); i++) {
        float x = float(i) * step;
        float dx1 = x - s1x, dy1 = y - s1y;
        float dx2 = x - s2x, dy2 = y - s2y;
        float d1 = std::sqrt(dx1 * dx1 + dy1 * dy1);
        float d2 = std::sqrt(dx2 * dx2 + dy2 * dy2);
        float v = std::sin(d1 * 0.085f - t * 2.4f) + std::sin(d2 * 0.07f - t * 1.9f);
        float k = (v + 2.0f) * 0.25f;
        int b = int(k * 5.99f);
        if (b < 0) b = 0; if (b > 5) b = 5;
        buckets[b].push_back({x, y + (k - 0.5f) * step * 0.55f * amp});
      }
    }
  }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    Paint bg; bg.color = Color::argb(0xff03071c);
    c.rect({0, 0, w, h}, bg);
    const uint32_t pal[6] = {0xff0a1b4a, 0xff123a8a, 0xff1f6fd0,
      0xff35b3f0, 0xff7fe9ff, 0xffd9fbff};
    for (int b = 0; b < 6; b++) {
      if (buckets[b].empty()) continue;
      Color cc = Color::argb(pal[b]);
      Paint p; p.blend = Blend::plus;
      p.color = {cc.r, cc.g, cc.b, (0.55f + 0.45f * f.music.energy) * f.intensity};
      c.points(buckets[b], (1.0f + float(b) / 5.0f * step * 0.42f) * 0.5f, p);
    }
  }
};
''';
