// Vórtice Hipnótico — port de la galería immersive a escena nativa.
// 42 anillos hexagonales de colores girando hacia el centro luminoso.
const nativeSource = r'''
class Visual final : public Scene {
  std::vector<Color> hues;
  float spin = 0;
 public:
  void reset(uint32_t seed) override {
    (void)seed; hues.clear(); spin = 0;
    for (int i = 0; i < 60; i++) {
      float hh = std::fmod(float(i * 6), 360.0f) / 60.0f;
      int s = int(hh) % 6;
      float fr = hh - std::floor(hh);
      float v = 0.92f, p = 0.0f, q = v * (1.0f - fr), u = v * fr;
      float r = p, g = p, b = p;
      if (s == 0) { r = v; g = u; } else if (s == 1) { r = q; g = v; }
      else if (s == 2) { g = v; b = u; } else if (s == 3) { g = q; b = v; }
      else if (s == 4) { b = v; r = u; } else { r = v; b = q; }
      hues.push_back({r, g, b, 1.0f});
    }
  }
  void update(const Frame& f) override {
    spin += float(f.delta) * f.speed * (f.reducedMotion ? 0.15f : 0.35f);
  }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float t = float(f.time) * f.speed;
    float cx = w * 0.5f, cy = h * 0.5f;
    float maxR = std::max(w, h) * 0.62f;
    float boost = (0.75f + 0.5f * f.music.bass) * f.intensity;
    Paint bg; bg.color = Color::argb(0xff05010e);
    c.rect({0, 0, w, h}, bg);
    for (int i = 0; i < 42; i++) {
      float z = std::fmod(float(i) / 42.0f + t * 0.16f, 1.0f);
      z = z * z;
      float rad = z * maxR + 6.0f;
      float rot = z * 2.2f + spin;
      float wob = std::sin(t * 0.8f + float(i) * 0.3f) * 0.12f;
      float a = std::min(1.0f, z * 2.4f) * (1.0f - z * 0.75f) * 0.95f;
      Color hc = hues[(i * 3 + int(t * 22.0f)) % 60];
      Path hex;
      for (int s = 0; s <= 6; s++) {
        float ang = float(s) / 6.0f * 6.2831853f + rot;
        float rr = rad * (1.0f + std::sin(ang * 3.0f + t) * wob);
        float x = cx + std::cos(ang) * rr, y = cy + std::sin(ang) * rr;
        if (s == 0) hex.moveTo(x, y); else hex.lineTo(x, y);
      }
      hex.close();
      Paint p; p.blend = Blend::plus;
      p.color = {hc.r, hc.g, hc.b, a * boost};
      p.strokeWidth = 1.0f + z * 3.5f;
      c.path(hex, p);
    }
    Paint core = Paint::radial({cx, cy}, std::min(w, h) * 0.3f,
      {{1, 1, 1, (0.85f + 0.15f * f.music.spark) * boost}, {0.667f, 0.353f, 1, 0.35f * boost},
       {0, 0, 0, 0}}, {0, 0.25f, 1.0f});
    core.blend = Blend::plus;
    c.rect({0, 0, w, h}, core);
  }
};
''';
