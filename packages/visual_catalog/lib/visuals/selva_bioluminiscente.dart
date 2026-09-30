// Árbol Bioluminiscente — port de la galería immersive a escena nativa.
// Fractal verde que respira con la música, esporas flotando y puntas brillantes.
const nativeSource = r'''
class Visual final : public Scene {
  struct Seg { float x1, y1, x2, y2; int level; };
  struct Spore { float x, y, speed, phase; };
  std::vector<Seg> segs[10];
  std::vector<Vec2> tips;
  std::vector<Spore> spores;
  float treeTime = 0.0f;
  float smoothEnergy = 0.0f;
  float smoothBass = 0.0f;
  float motion = 1.0f;
  void grow(float x, float y, float a, float len, int d, float seed, float t) {
    float sway = std::sin(seed * 0.7f + t * 0.25f) * float(9 - d) * 0.025f * motion;
    float na = a + sway;
    float x2 = x + std::cos(na) * len, y2 = y + std::sin(na) * len;
    segs[9 - d].push_back({x, y, x2, y2, 9 - d});
    if (d <= 1) {
      if (tips.size() < 256) tips.push_back({x2, y2});
      return;
    }
    float spread = 0.42f + std::sin(t * 0.4f + seed) * 0.07f;
    grow(x2, y2, na - spread, len * 0.74f, d - 1, seed * 2.0f + 1.0f, t);
    grow(x2, y2, na + spread, len * 0.74f, d - 1, seed * 2.0f + 2.0f, t);
  }
 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    spores.clear(); motion = 1.0f;
    treeTime = 0.0f; smoothEnergy = 0.0f; smoothBass = 0.0f;
    for (int i = 0; i < 70; i++)
      spores.push_back({rng.unit(), rng.unit(), 0.3f + rng.unit() * 1.2f, rng.unit() * 6.2831853f});
  }
  void update(const Frame& f) override {
    float dt = float(f.delta);
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    smoothEnergy += (targetEnergy - smoothEnergy) * float(1.0 - std::exp(-dt * 5.0));
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 6.0));

    // En silencio reposa en un vaivén suave y meditativo (~0.12f).
    // Con música la selva bioluminiscente respira y late con el audio.
    float audioDrive = 0.12f + smoothEnergy * 0.75f + smoothBass * 0.35f;
    treeTime += dt * f.speed * audioDrive;

    float t = treeTime;
    motion = f.reducedMotion ? 0.3f : 1.0f;
    for (int i = 0; i < 10; i++) segs[i].clear();
    tips.clear();
    grow(f.width * 0.5f, f.height * 0.94f, -1.5707963f, f.height * (0.16f + smoothBass * 0.035f), 9, 1.0f, t);
  }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float t = treeTime;
    float boost = std::clamp((0.8f + 0.4f * smoothEnergy + 0.3f * smoothBass) * f.intensity, 0.0f, 1.0f);
    Paint bg = Paint::radial({w * 0.5f, h * 0.75f}, h * 0.9f,
      {Color::argb(0xff04231c), Color::argb(0xff021410), Color::argb(0xff000705)}, {0, 0.5f, 1.0f});
    c.rect({0, 0, w, h}, bg);
    std::vector<Vec2> sbuf; sbuf.reserve(spores.size());
    for (const auto& s : spores) {
      float y = std::fmod(s.y * h - t * s.speed * 9.0f, h);
      if (y < 0) y += h;
      sbuf.push_back({s.x * w + std::sin(t * 0.6f + s.phase) * 12.0f, y});
    }
    Paint sp; sp.blend = Blend::plus;
    sp.color = {0.435f, 1, 0.753f, 0.4f * boost};
    c.points(sbuf, 1.0f, sp);
    const uint32_t cols[10] = {0xff0b3a2e, 0xff0f5c42, 0xff14855a, 0xff1fb573, 0xff43e08f,
      0xff7bffb0, 0xffb9ffd6, 0xffe6fff1, 0xffffffff, 0xffffffff};
    for (int i = 0; i < 10; i++) {
      Path path;
      for (const auto& s : segs[i]) {
        path.moveTo(s.x1, s.y1); path.lineTo(s.x2, s.y2);
      }
      Paint p; p.blend = Blend::plus;
      Color cc = Color::argb(cols[i]);
      p.color = {cc.r, cc.g, cc.b, 0.85f * boost};
      p.strokeWidth = std::max(0.6f, float(9 - i) * 0.52f);
      c.path(path, p);
    }
    Paint tp; tp.blend = Blend::plus;
    tp.color = {0.788f, 1, 0.902f, (0.45f + 0.45f * std::abs(std::sin(t * 2.0f))) * boost};
    c.points(tips, 1.6f, tp);
  }
};
''';
