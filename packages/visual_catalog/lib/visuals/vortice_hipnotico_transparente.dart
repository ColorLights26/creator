// Vórtice Hipnótico Transparente — versión overlay sin fondo opaco.
const nativeSource = r'''
class Visual final : public Scene {
  float vortexTime = 0.0f;
  float spin = 0.0f;
  float smoothBass = 0.0f;
  float smoothEnergy = 0.0f;
  float smoothSpark = 0.0f;
 public:
  void reset(uint32_t seed) override {
    (void)seed;
    vortexTime = 0.0f;
    spin = 0.0f;
    smoothBass = 0.0f;
    smoothEnergy = 0.0f;
    smoothSpark = 0.0f;
  }
  void update(const Frame& f) override {
    float dt = float(f.delta);
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    float targetSpark = f.music.active ? f.music.spark : 0.0f;
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 6.0));
    smoothEnergy += (targetEnergy - smoothEnergy) * float(1.0 - std::exp(-dt * 5.0));
    smoothSpark += (targetSpark - smoothSpark) * float(1.0 - std::exp(-dt * 15.0));

    // En silencio reposa en un giro hipnótico pausado (~0.10f).
    // Con música acelera la absorción vórtice y los cambios de tono.
    float audioDrive = 0.10f + smoothEnergy * 0.75f + smoothBass * 0.35f;
    vortexTime += dt * f.speed * audioDrive;
    spin += dt * f.speed * audioDrive * (f.reducedMotion ? 0.15f : 0.35f);
  }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float t = vortexTime;
    float cx = w * 0.5f, cy = h * 0.5f;
    float maxR = std::max(w, h) * 0.62f;
    float boost = std::clamp((0.75f + 0.5f * smoothBass) * f.intensity, 0.0f, 1.0f);
    for (int i = 0; i < 42; i++) {
      float z = std::fmod(float(i) / 42.0f + t * 0.16f, 1.0f);
      z = z * z;
      float rad = z * maxR + 6.0f;
      float rot = z * 2.2f + spin;
      float wob = std::sin(t * 0.8f + float(i) * 0.3f) * 0.12f;
      float a = std::min(1.0f, z * 2.4f) * (1.0f - z * 0.75f) * 0.95f;
      float hue = std::fmod(float(i) * 6.0f + t * 44.0f, 360.0f) / 60.0f;
      int seg = int(hue) % 6;
      float fr = hue - std::floor(hue);
      const float v = 0.92f;
      float q = v * (1.0f - fr), u = v * fr;
      float r = 0, g = 0, b = 0;
      if (seg == 0) { r = v; g = u; }
      else if (seg == 1) { r = q; g = v; }
      else if (seg == 2) { g = v; b = u; }
      else if (seg == 3) { g = q; b = v; }
      else if (seg == 4) { b = v; r = u; }
      else { r = v; b = q; }
      Path hex;
      for (int s = 0; s <= 6; s++) {
        float ang = float(s) / 6.0f * 6.2831853f + rot;
        float rr = rad * (1.0f + std::sin(ang * 3.0f + t) * wob);
        float x = cx + std::cos(ang) * rr, y = cy + std::sin(ang) * rr;
        if (s == 0) hex.moveTo(x, y); else hex.lineTo(x, y);
      }
      hex.close();
      Paint p; p.blend = Blend::plus;
      p.color = {r, g, b, a * boost};
      p.strokeWidth = 1.0f + z * 3.5f;
      c.path(hex, p);
    }
    Paint core = Paint::radial({cx, cy}, std::min(w, h) * 0.3f,
      {{1, 1, 1, (0.85f + 0.15f * f.music.spark) * boost}, {0.667f, 0.353f, 1, 0.35f * boost},
       {0, 0, 0, 0}}, {0.0f, 0.25f, 1.0f});
    core.blend = Blend::plus;
    c.circle({cx, cy}, std::min(w, h) * 0.3f, core);
  }
};
''';
