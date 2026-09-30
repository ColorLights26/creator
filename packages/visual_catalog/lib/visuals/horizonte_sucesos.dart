// Horizonte de Sucesos — puerto de la galería FLUX/10 al motor nativo.
// Disco de acreción en cuatro bandas de calor y dos pasadas (detrás / delante)
// para resolver el orden sin z-buffer, anillo fotónico, arco de Einstein y
// deflexión gravitatoria del campo de estrellas.
const nativeSource = r'''
class Visual final : public Scene {
  struct Part { float r, a0, spd, w; };
  struct Star { float x, y, m; };
  std::vector<Part> parts;
  std::vector<Star> stars;
 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    parts.clear(); stars.clear();
    int np = 620;
    parts.reserve(np);
    for (int i = 0; i < np; i++) {
      Part p;
      float u = rng.unit();
      p.r = 1.55f + std::pow(u, 0.62f) * 3.6f;
      p.a0 = rng.unit() * 6.2831853f;
      // Kepler: la velocidad angular cae con r^1.5 => rotación diferencial real.
      p.spd = 1.0f / (p.r * std::sqrt(p.r));
      p.w = 0.5f + rng.unit() * 2.2f;
      parts.push_back(p);
    }
    stars.reserve(320);
    for (int i = 0; i < 320; i++) {
      Star s; s.x = rng.unit(); s.y = rng.unit(); s.m = rng.unit();
      stars.push_back(s);
    }
  }
  void update(const Frame& f) override { (void)f; }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float t = float(f.time) * f.speed;
    float cx = w * 0.5f, cy = h * 0.5f;
    float rs = std::min(w, h) * 0.13f;
    float yaw = std::sin(t * 0.09f) * 0.22f * (1.0f + f.music.energy * 0.3f);
    float squash = 0.24f + std::cos(t * 0.07f) * 0.14f;
    float boost = (0.85f + 0.35f * f.music.energy) * f.intensity;
    if (boost > 1.0f) boost = 1.0f; if (boost < 0.0f) boost = 0.0f;
    float spin = t * 0.06f * (f.reducedMotion ? 0.3f : 1.0f);
    Paint bg; bg.color = Color::argb(0xff030308);
    c.rect({0, 0, w, h}, bg);

    // ── Estrellas con deflexión gravitatoria ──
    std::vector<Vec2> field;
    field.reserve(stars.size());
    for (const auto& s : stars) {
      float bx = s.x * w, by = s.y * h;
      float dx = bx - cx, dy = by - cy;
      float d = std::sqrt(dx * dx + dy * dy) + 1.0f;
      if (d < rs * 1.25f) continue; // devoradas por la sombra
      float k = 1.0f + (rs * rs * 5.2f) / (d * d);
      field.push_back({cx + dx * k, cy + dy * k});
    }
    Paint sp; sp.blend = Blend::plus;
    sp.color = {0.863f, 0.910f, 1, 0.69f * boost};
    c.points(field, 1.1f, sp);

    const uint32_t ramp[4] = {0xffc9432a, 0xffff8f4a, 0xffffd166, 0xfffff3d0};

    // Disco: cuatro bandas de calor, dos pasadas para el orden.
    for (int pass = 0; pass < 2; pass++) {
      for (int b = 0; b < 4; b++) {
        Path disk;
        for (const auto& p : parts) {
          float heat = 1.0f - (p.r - 1.55f) / 3.6f;
          if (heat < 0.0f) heat = 0.0f; if (heat > 1.0f) heat = 1.0f;
          if (int(heat * 3.999f) != b) continue;
          float rad = p.r * rs;
          float a = p.a0 + spin * p.spd + yaw;
          float sa = std::sin(a);
          if ((sa < 0.0f ? 0 : 1) != pass) continue;
          float x = cx + std::cos(a) * rad;
          float y = cy + sa * rad * squash;
          float len = p.w * (2.2f + heat * 6.0f);
          disk.moveTo(x + std::sin(a) * len, y - std::cos(a) * squash * len);
          disk.lineTo(x, y);
        }
        Color cc = Color::argb(ramp[b]);
        Paint dp; dp.blend = Blend::plus;
        dp.color = {cc.r, cc.g, cc.b, (0.10f + float(b) * 0.14f) * boost};
        dp.strokeWidth = 0.7f + float(b) * 0.5f;
        dp.strokeCap = 1; dp.strokeJoin = 1;
        c.path(disk, dp);
      }
      if (pass == 0) {
        // ── Anillo fotónico ──
        float ringR = rs * 1.34f;
        Paint rp; rp.blend = Blend::plus;
        for (int i = 3; i >= 1; i--) {
          rp.color = {1, 0.819f, 0.400f, 0.051f * boost};
          rp.strokeWidth = rs * 0.16f * float(i);
          c.circle({cx, cy}, ringR * (1.0f + float(i) * 0.07f), rp);
        }
        Paint crisp; crisp.blend = Blend::plus;
        crisp.color = {1, 0.941f, 0.824f, 0.949f * boost};
        crisp.strokeWidth = std::max(1.0f, rs * 0.045f);
        c.circle({cx, cy}, ringR, crisp);
        // ── Sombra del horizonte ──
        Paint shadow; shadow.color = {0, 0, 0, 1};
        c.circle({cx, cy}, rs, shadow);
      }
    }

    // ── Arco de Einstein: imagen lensada del disco sobre el horizonte ──
    Path arc;
    const int steps = 48;
    for (int i = 0; i <= steps; i++) {
      float a = 3.14159265f * 1.06f + float(i) / float(steps) * 3.14159265f * 0.88f;
      float x = cx + std::cos(a) * rs * 1.16f;
      float y = cy + std::sin(a) * rs * 1.16f;
      if (i == 0) arc.moveTo(x, y); else arc.lineTo(x, y);
    }
    Paint ap; ap.blend = Blend::plus;
    ap.color = {1, 0.722f, 0.361f, 0.502f * boost};
    ap.strokeWidth = rs * 0.2f; ap.strokeCap = 1; ap.strokeJoin = 1;
    c.path(arc, ap);

    // Resplandor global.
    Paint glow = Paint::radial({cx, cy}, rs * 6.5f,
      {{1, 0.667f, 0.314f, 0.141f * boost}, {0.627f, 0.314f, 1, 0.051f * boost}, {0, 0, 0, 0}},
      {0.0f, 0.4f, 1.0f});
    glow.blend = Blend::plus;
    c.rect({0, 0, w, h}, glow);
  }
};
''';
