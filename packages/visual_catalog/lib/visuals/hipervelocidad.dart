// Hipervelocidad — port de la galería immersive a escena nativa.
// Estelas reales por segmentos, agrupadas en tres lotes por color.
const nativeSource = r'''
class Visual final : public Scene {
  struct Star { float x, y, z; };
  std::vector<Star> stars;
  Random rng_{1234};
  void seedOne(Star& s, float w, float h, bool far) {
    s.x = (rng_.unit() - 0.5f) * w * 2.2f;
    s.y = (rng_.unit() - 0.5f) * h * 2.2f;
    s.z = far ? 1.0f + rng_.unit() * 1.2f : rng_.unit() * 2.2f + 0.05f;
  }
 public:
  void reset(uint32_t seed) override {
    rng_ = Random(seed ? seed : 1234);
    stars.clear(); stars.reserve(621);
    for (int i = 0; i < 621; i++) {
      Star s; seedOne(s, 400.0f, 700.0f, false);
      stars.push_back(s);
    }
  }
  void update(const Frame& f) override {
    float dt = std::min(float(f.delta), 0.05f);
    float speed = (1.1f + std::sin(float(f.time) * 0.25f) * 0.55f)
      * (f.reducedMotion ? 0.4f : 1.0f) * (1.0f + f.music.energy * 0.8f) * dt * 0.96f;
    for (auto& s : stars) {
      s.z -= speed;
      if (s.z <= 0.04f) seedOne(s, f.width, f.height, true);
    }
  }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float cx = w * 0.5f, cy = h * 0.5f;
    float boost = (0.7f + 0.5f * f.music.energy + 0.4f * f.music.bass) * f.intensity;
    Paint bg; bg.color = Color::argb(0xff02020c);
    c.rect({0, 0, w, h}, bg);
    Path lanes[3];
    std::vector<Vec2> heads[3];
    for (int i = 0; i < 3; i++) { heads[i].reserve(220); }
    for (size_t idx = 0; idx < stars.size(); idx++) {
      const Star& s = stars[idx];
      float x1 = cx + (s.x / s.z) * 0.75f;
      float y1 = cy + (s.y / s.z) * 0.75f;
      if (x1 < -80 || x1 > w + 80 || y1 < -80 || y1 > h + 80) continue;
      float tail = s.z + 0.11f;
      int lane = int(idx % 3);
      lanes[lane].moveTo(cx + (s.x / tail) * 0.75f, cy + (s.y / tail) * 0.75f);
      lanes[lane].lineTo(x1, y1);
      heads[lane].push_back({x1, y1});
    }
    for (int lane = 0; lane < 3; lane++) {
      Paint p; p.blend = Blend::plus;
      if (lane == 0) { p.color = {1, 1, 1, 0.9f * boost}; p.strokeWidth = 1.7f; }
      else if (lane == 1) { p.color = {0.749f, 0.894f, 1, 0.55f * boost}; p.strokeWidth = 1.1f; }
      else { p.color = {1, 0.839f, 0.941f, 0.55f * boost}; p.strokeWidth = 1.1f; }
      p.strokeCap = 1; p.strokeJoin = 1;
      c.path(lanes[lane], p);
      if (!heads[lane].empty()) {
        Paint hp; hp.blend = Blend::plus;
        hp.color = {1, 1, 1, 0.85f * boost};
        c.points(heads[lane], 0.85f, hp);
      }
    }
    Paint glow = Paint::radial({cx, cy}, std::min(w, h) * 0.45f,
      {{0.549f, 0.745f, 1, 0.28f * boost}, {0, 0, 0, 0}});
    glow.blend = Blend::plus;
    c.rect({0, 0, w, h}, glow);
  }
};
''';
