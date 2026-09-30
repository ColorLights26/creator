// Hipervelocidad — port de la galería immersive a escena nativa.
// Estelas reales por segmentos, agrupadas en tres lotes por color. La
// posición es función pura del tiempo, así que 30 y 60 FPS coinciden.
const nativeSource = r'''
class Visual final : public Scene {
  struct Star { float x, y, z0, cycle; };
  std::vector<Star> stars;
  float travel = 0.0f;
  float smoothBass = 0.0f;
  float smoothEnergy = 0.0f;
 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    stars.clear(); stars.reserve(621);
    travel = 0.0f; smoothBass = 0.0f; smoothEnergy = 0.0f;
    for (int i = 0; i < 621; i++) {
      Star s;
      s.x = (rng.unit() - 0.5f) * 2.2f;
      s.y = (rng.unit() - 0.5f) * 2.2f;
      s.z0 = rng.unit() * 2.2f + 0.05f;
      s.cycle = 2.2f + 1.2f;
      stars.push_back(s);
    }
  }
  void update(const Frame& f) override {
    float dt = float(f.delta);
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 6.0));
    smoothEnergy += (targetEnergy - smoothEnergy) * float(1.0 - std::exp(-dt * 5.0));

    // En silencio reposa en un crucero estelar pausado (~0.10f).
    // Con música acelera hacia velocidad hiperlumínica con estelas largas.
    float audioDrive = 0.10f + smoothEnergy * 0.90f + smoothBass * 0.45f;
    if (f.reducedMotion) audioDrive *= 0.4f;
    travel += dt * f.speed * audioDrive * 1.6f;
  }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float cx = w * 0.5f, cy = h * 0.5f;
    float boost = std::clamp((0.7f + 0.5f * smoothEnergy + 0.4f * smoothBass) * f.intensity, 0.0f, 1.0f);
    Paint bg; bg.color = Color::argb(0xff02020c);
    c.rect({0, 0, w, h}, bg);
    Path lanes[3];
    std::vector<Vec2> heads[3];
    for (int i = 0; i < 3; i++) heads[i].reserve(240);
    for (size_t idx = 0; idx < stars.size(); idx++) {
      const Star& s = stars[idx];
      float z = std::fmod(s.z0 - travel, s.cycle);
      if (z < 0.04f) z += s.cycle;
      float x1 = cx + (s.x / z) * 0.75f;
      float y1 = cy + (s.y / z) * 0.75f;
      if (x1 < -80 || x1 > w + 80 || y1 < -80 || y1 > h + 80) continue;
      float tail = z + 0.04f + smoothEnergy * 0.10f;
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
