// Caleidoscopio — port de la galería immersive a escena nativa.
// 12 segmentos espejados con pétalos, anillos y destellos girando.
const nativeSource = r'''
class Visual final : public Scene {
  float spin = 0;
 public:
  void reset(uint32_t seed) override { (void)seed; spin = 0; }
  void update(const Frame& f) override {
    spin += float(f.delta) * f.speed * (f.reducedMotion ? 0.05f : 0.12f);
  }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float t = float(f.time) * f.speed;
    float cx = w * 0.5f, cy = h * 0.5f;
    float r = std::min(w, h) * 0.52f;
    float boost = (0.7f + 0.5f * f.music.energy) * f.intensity;
    Paint bg; bg.color = Color::argb(0xff07020f);
    c.rect({0, 0, w, h}, bg);
    const uint32_t pet[5] = {0xffff2e9a, 0xffffb03a, 0xff3ef0ff, 0xffa06bff, 0xff7dff9e};
    for (int s = 0; s < 12; s++) {
      c.save();
      c.translate(cx, cy);
      c.rotate(float(s) / 12.0f * 6.2831853f + spin);
      float mirror = (s % 2 == 1) ? -1.0f : 1.0f;
      for (int i = 0; i < 6; i++) {
        float p = float(i) / 6.0f;
        float rr = r * (0.18f + p * 0.78f) * (0.85f + std::sin(t * 0.9f + float(i)) * 0.15f);
        float a = 0.22f + std::sin(t * 0.5f + float(i) * 0.8f) * 0.16f;
        Color pc = Color::argb(pet[i % 5]);
        Path petal;
        petal.moveTo(0, 0);
        petal.quadraticTo(rr * 0.6f, -rr * a * mirror, rr, 0);
        petal.quadraticTo(rr * 0.6f, rr * a * 0.35f * mirror, 0, 0);
        petal.close();
        Paint fp; fp.blend = Blend::plus;
        fp.color = {pc.r, pc.g, pc.b, (0.16f + 0.12f * std::abs(std::sin(t + float(i)))) * boost};
        c.path(petal, fp);
      }
      for (int i = 0; i < 5; i++) {
        float rr = r * (0.2f + float(i) * 0.18f) + std::sin(t * 1.3f + float(i) * 1.1f) * r * 0.05f;
        Color rc = Color::argb(pet[(i + 2) % 5]);
        Path arc;
        for (int k = 0; k <= 16; k++) {
          float ang = -0.26f + float(k) / 16.0f * 0.52f;
          float x = std::cos(ang) * rr, y = std::sin(ang) * rr * mirror;
          if (k == 0) arc.moveTo(x, y); else arc.lineTo(x, y);
        }
        Paint rp; rp.blend = Blend::plus;
        rp.color = {rc.r, rc.g, rc.b, 0.5f * boost};
        rp.strokeWidth = 1.2f;
        c.path(arc, rp);
      }
      std::vector<Vec2> sparks;
      for (int i = 0; i < 4; i++) {
        float rr = r * (0.3f + std::fmod(float(i) * 0.21f + t * 0.14f, 0.68f));
        sparks.push_back({rr, rr * std::sin(t * 2.0f + float(i) * 2.1f) * 0.18f * mirror});
      }
      Paint kp; kp.blend = Blend::plus;
      kp.color = {1, 1, 1, 0.8f * boost};
      c.points(sparks, 2.4f, kp);
      c.restore();
    }
    Paint core = Paint::radial({cx, cy}, r * 0.5f,
      {{1, 1, 1, 0.5f * boost}, {1, 0.47f, 0.86f, 0.12f * boost}, {0, 0, 0, 0}}, {0, 0.4f, 1.0f});
    core.blend = Blend::plus;
    c.rect({0, 0, w, h}, core);
  }
};
''';
