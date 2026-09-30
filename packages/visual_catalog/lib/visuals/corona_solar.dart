// Corona Solar — puerto de la galería FLUX/10 al motor nativo.
// limbo deformado por 7 armónicos, 96 filamentos de corona y halo en tres
// pasadas. La energía del gesto se sustituye por la música.
const nativeSource = r'''
class Visual final : public Scene {
 public:
  void reset(uint32_t seed) override { (void)seed; }
  void update(const Frame& f) override { (void)f; }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float t = float(f.time) * f.speed;
    float time = t * 6.2831853f;
    float energy = std::min(1.4f, f.music.energy * 1.6f + f.music.bass * 0.8f) * f.intensity;
    float cx = w * 0.5f, cy = h * 0.5f;
    float rad = std::min(w, h) * 0.24f;
    Paint bg = Paint::radial({cx, cy}, std::max(w, h) * 1.1f,
      {Color::argb(0xff1b0d05), Color::argb(0xff0a0608), Color::argb(0xff04040a)},
      {0.0f, 0.5f, 1.0f});
    c.rect({0, 0, w, h}, bg);

    // ── Filamentos de corona: un Path, 96 rayos ──
    Path rays;
    for (int i = 0; i < 96; i++) {
      float a = float(i) / 96.0f * 6.2831853f;
      float n = std::sin(a * 9.0f + time * 1.4f) * 0.5f + std::sin(a * 23.0f - time * 0.9f) * 0.5f;
      float len = rad * (1.25f + std::abs(n) * (1.5f + energy));
      rays.moveTo(cx + std::cos(a) * rad * 1.02f, cy + std::sin(a) * rad * 1.02f);
      rays.lineTo(cx + std::cos(a + 0.01f) * len, cy + std::sin(a + 0.01f) * len);
    }
    Paint add; add.blend = Blend::plus;
    add.color = {1, 0.416f, 0.333f, 0.102f};
    add.strokeWidth = 1.6f; add.strokeCap = 1; add.strokeJoin = 1;
    c.path(rays, add);

    // ── Halo en tres pasadas (bloom falso, sin saveLayer) ──
    for (int i = 3; i >= 1; i--) {
      Paint hp; hp.blend = Blend::plus;
      hp.color = {0.961f, 0.647f, 0.141f, 0.043f};
      c.circle({cx, cy}, rad * (1.0f + float(i) * 0.42f + energy * 0.1f), hp);
    }

    // ── limbo ──
    static const float harm[7][3] = {
      {5, 0.055f, 0.90f}, {8, 0.032f, -1.40f}, {13, 0.022f, 2.10f},
      {3, 0.048f, -0.60f}, {21, 0.012f, 3.00f}, {2, 0.050f, 0.45f},
      {34, 0.008f, -2.40f}};
    Path limb;
    const int steps = 128;
    for (int i = 0; i <= steps; i++) {
      float a = float(i) / float(steps) * 6.2831853f;
      float d = 1.0f;
      for (int k = 0; k < 7; k++)
        d += harm[k][1] * std::sin(a * harm[k][0] + time * harm[k][2]) * (1.0f + energy * 0.8f);
      float r = rad * d * (1.0f + std::sin(time * 2.2f) * 0.012f);
      float x = cx + std::cos(a) * r, y = cy + std::sin(a) * r;
      if (i == 0) limb.moveTo(x, y); else limb.lineTo(x, y);
    }
    limb.close();
    Paint limbPaint = Paint::radial({cx - rad * 0.25f, cy - rad * 0.3f}, rad * 1.3f,
      {Color::argb(0xfffff6d8), Color::argb(0xfff5a524),
       Color::argb(0xe6e8541f), Color::argb(0xe65a0a1e)},
      {0.0f, 0.35f, 0.78f, 1.0f});
    c.path(limb, limbPaint);

    // ── Gránulos de plasma recortados al limbo ──
    c.save();
    c.clip(limb);
    for (int i = 0; i < 26; i++) {
      float a = time * 0.35f + float(i) * 2.399f;
      float rr = rad * (0.25f + float((i * 37) % 70) / 100.0f);
      Paint gp;
      if (i % 3 == 0) gp.color = {1, 0.941f, 0.753f, 0.22f};
      else gp.color = {1, 0.353f, 0.157f, 0.188f};
      c.circle({cx + std::cos(a) * rr, cy + std::sin(a * 1.3f) * rr},
        rad * (0.10f + float(i % 5) * 0.035f), gp);
    }
    c.restore();
  }
};
''';
